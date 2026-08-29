<#
.SYNOPSIS
    Ensures Node.js and npm are available without admin rights or GUI installers.
.DESCRIPTION
    The winget package ID and the post-install search paths come from
    config/dev-setup.config.json, so they cannot drift apart.
#>
param(
    [string]$NodePackage,
    [switch]$Audit
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig

if (-not $NodePackage) {
    $NodePackage = Get-DevSetupValue $config "advanced.node.wingetPackageId" "OpenJS.NodeJS.LTS"
}

$nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue

if ($Audit) {
    if ($nodeCommand -and $npmCommand) {
        Write-DevSetupStatus found "Node.js" "$(& $nodeCommand.Source --version) at $($nodeCommand.Source)"
    } elseif (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        Write-DevSetupStatus install "Node.js" "would install $NodePackage via winget"
    } else {
        Write-DevSetupStatus warn "Node.js" "missing and winget is unavailable"
    }
    return
}

if (-not $nodeCommand -or -not $npmCommand) {
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        throw "Node.js and npm are unavailable and winget is not installed. Install Node.js LTS from https://nodejs.org/ or provide winget.exe in PATH. No GUI installer was launched."
    }

    Write-DevSetupStatus install "Node.js" "installing $NodePackage via winget (per-user, no admin, no GUI)"
    & winget.exe install --id $NodePackage -e --scope user --accept-package-agreements --accept-source-agreements --silent

    $configuredPaths = Get-DevSetupValue $config "advanced.node.windowsSearchPaths" @(
        "%ProgramFiles%\nodejs\node.exe",
        "%LOCALAPPDATA%\Programs\nodejs\node.exe",
        "%LOCALAPPDATA%\Microsoft\WinGet\Packages\{wingetPackageId}*\node-v*\node.exe"
    )
    $nodePaths = $configuredPaths | ForEach-Object {
        Expand-DevSetupPath ($_ -replace '\{wingetPackageId\}', $NodePackage)
    }
    $nodePath = $nodePaths | ForEach-Object { Get-ChildItem $_ -File -ErrorAction SilentlyContinue } | Select-Object -First 1
    if ($nodePath) {
        $nodeCommand = $nodePath
        $env:Path = "$($nodeCommand.DirectoryName);$env:Path"
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notlike "*$($nodeCommand.DirectoryName)*") {
            [Environment]::SetEnvironmentVariable("Path", "$($nodeCommand.DirectoryName);$userPath", "User")
        }
    } else {
        $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
    }
}

if (-not $nodeCommand) {
    throw "Node.js setup completed but node.exe was not found. Open a new terminal and run setup again."
}

$nodeLocation = if ($nodeCommand.Source) { $nodeCommand.Source } else { $nodeCommand.FullName }
$env:Path = "$(Split-Path -Parent $nodeLocation);$env:Path"
$npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npmCommand) {
    throw "Node.js is available at $nodeLocation, but npm.cmd was not found. Open a new terminal and run setup again."
}

Write-DevSetupStatus found "Node.js" "$(& $nodeLocation --version) at $nodeLocation"
Write-DevSetupStatus found "npm" "$(& $npmCommand.Source --version) at $($npmCommand.Source)"
Write-Host "  If PowerShell blocks npm.ps1, use npm.cmd instead of npm (for example: npm.cmd test)." -ForegroundColor DarkGray
