<#
.SYNOPSIS
    Loads the dev-setup config and provides safe lookup and reporting helpers.
.DESCRIPTION
    Dot-source this file, then call Get-DevSetupConfig once and read values with
    Get-DevSetupValue. Every lookup takes a fallback, so a config file that is
    missing keys degrades to the built-in default instead of failing the run.

    $DevSetupRoot is the repository root, resolved from this file's location, so
    callers in src/scripts/ and in the root both work without hardcoding paths.
#>

$DevSetupRoot = Split-Path -Parent $PSScriptRoot
$DevSetupConfigPath = Join-Path $DevSetupRoot "config\dev-setup.config.json"

function Get-DevSetupConfig {
    param([string]$Path)

    if (-not $Path) { $Path = $DevSetupConfigPath }
    if (-not (Test-Path $Path)) {
        Write-Warning "Config file not found at $Path. Using built-in defaults."
        return [pscustomobject]@{}
    }

    try {
        return Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        throw "Config file $Path is not valid JSON: $($_.Exception.Message)"
    }
}

function Get-DevSetupValue {
    param(
        $Config,
        [string]$Key,
        $Default = $null
    )

    $node = $Config
    foreach ($segment in $Key.Split(".")) {
        if ($null -eq $node) { return $Default }
        $property = $node.PSObject.Properties[$segment]
        if (-not $property) { return $Default }
        $node = $property.Value
    }

    # Treat null and empty string as "not set" so blank config entries fall back.
    if ($null -eq $node) { return $Default }
    if ($node -is [string] -and $node -eq "") { return $Default }
    return $node
}

function Expand-DevSetupPath {
    param([string]$Value)

    if (-not $Value) { return $Value }
    return [Environment]::ExpandEnvironmentVariables($Value)
}

function ConvertTo-DevSetupHashtable {
    <# PSCustomObject from ConvertFrom-Json -> hashtable, for iteration. #>
    param($Value)

    $result = [ordered]@{}
    if ($null -eq $Value) { return $result }
    foreach ($property in $Value.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    return $result
}

function Write-DevSetupStatus {
    <#
    .SYNOPSIS
        One audit line per component so a run reads as a report.
    .DESCRIPTION
        found   - already present, nothing to do
        install - something is about to change
        skip    - disabled in config, or not applicable on this platform
        warn    - proceeded, but the result is degraded
    #>
    param(
        [Parameter(Mandatory)][ValidateSet("found", "install", "skip", "warn")][string]$State,
        [Parameter(Mandatory)][string]$Component,
        [string]$Detail = ""
    )

    $color = switch ($State) {
        "found"   { "Green" }
        "install" { "Cyan" }
        "skip"    { "DarkGray" }
        "warn"    { "Yellow" }
    }
    Write-Host ("  {0,-9} {1,-8} {2}" -f "[$State]", $Component, $Detail) -ForegroundColor $color
}

function Get-DevSetupVSCodeProfilePath {
    <# Resolved settings.json paths for the profiles named in user.vscode.profiles. #>
    param($Config, [string]$Platform = "windows")

    $names = Get-DevSetupValue $Config "user.vscode.profiles" @("stable", "insiders")
    $dirs = ConvertTo-DevSetupHashtable (Get-DevSetupValue $Config "advanced.vscode.profileDirectories.$Platform")

    foreach ($name in $names) {
        if (-not $dirs.Contains($name)) { continue }
        $settingsPath = Join-Path (Expand-DevSetupPath $dirs[$name]) "settings.json"
        if (Test-Path $settingsPath) {
            [pscustomobject]@{ Name = $name; Path = $settingsPath }
        }
    }
}

function Set-DevSetupVSCodeSetting {
    <#
    .SYNOPSIS
        Write one setting into every configured VS Code profile, skipping no-ops.
    .DESCRIPTION
        Used for the machine-local paths that only the platform installers can
        resolve. Bulk settings are handled by src/configure-vscode.py instead.
    #>
    param($Config, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)]$Value)

    foreach ($vscodeProfile in Get-DevSetupVSCodeProfilePath $Config) {
        $settings = Get-Content $vscodeProfile.Path -Raw | ConvertFrom-Json
        $property = $settings.PSObject.Properties[$Key]
        if ($property -and $property.Value -eq $Value) {
            Write-DevSetupStatus found "vscode" "$Key already correct ($($vscodeProfile.Name))"
            continue
        }
        if ($property) { $property.Value = $Value }
        else { $settings | Add-Member -MemberType NoteProperty -Name $Key -Value $Value }
        ($settings | ConvertTo-Json -Depth 20) | Set-Content $vscodeProfile.Path
        Write-DevSetupStatus install "vscode" "$Key -> $Value ($($vscodeProfile.Name))"
    }
}

function Add-DevSetupUserPath {
    <#
    .SYNOPSIS
        Add a directory to the user-level PATH, once.
    .DESCRIPTION
        Compares whole PATH entries. A substring test would both miss paths
        containing PowerShell wildcard characters and wrongly treat
        C:\Python314 as present when only C:\Python314\Scripts is.
    #>
    param([Parameter(Mandatory)][string]$Directory, [switch]$Prepend)

    if (-not (Test-Path $Directory)) { return }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $target = $Directory.TrimEnd("\")
    $entries = @($userPath -split ";" | Where-Object { $_ } | ForEach-Object { $_.Trim().TrimEnd("\") })
    if ($entries -contains $target) { return }

    $updated = if ($Prepend) { "$Directory;$userPath" } else { "$userPath;$Directory" }
    [Environment]::SetEnvironmentVariable("Path", $updated, "User")
    Write-DevSetupStatus install "PATH" "added $Directory to the user PATH"
}

function Get-DevSetupGitCredentialSetting {
    <# The git config keys/values this setup owns on Windows. #>
    param($Config)

    @(
        [pscustomobject]@{
            Key = "credential.helper"
            Value = (Get-DevSetupValue $Config "advanced.git.credential.windows.helper" "manager")
            ReplaceAll = $true
        },
        [pscustomobject]@{
            Key = "credential.credentialStore"
            Value = (Get-DevSetupValue $Config "advanced.git.credential.windows.credentialStore" "wincredman")
            ReplaceAll = $false
        },
        [pscustomobject]@{
            # git expects lowercase true/false, not PowerShell's True/False.
            Key = "credential.guiPrompt"
            Value = "$(Get-DevSetupValue $Config 'advanced.git.credential.windows.guiPrompt' $false)".ToLowerInvariant()
            ReplaceAll = $false
        }
    )
}

function Write-DevSetupGitIdentityStatus {
    <# Reports identity state the same way in audit and apply runs. #>
    param($Config, [string]$GitExe, [switch]$Audit)

    $configured = Get-DevSetupValue $Config "user.git.userEmail"
    $current = (& $GitExe config --global --get user.email 2>$null)

    if ($configured) {
        $verb = if ($Audit) { "would apply" } else { "applied" }
        Write-DevSetupStatus install "identity" "$verb $configured from config"
    } elseif ($current) {
        Write-DevSetupStatus found "identity" "already set to $current"
    } else {
        Write-DevSetupStatus warn "identity" "not set; fill user.git.userName / user.git.userEmail"
    }
}
