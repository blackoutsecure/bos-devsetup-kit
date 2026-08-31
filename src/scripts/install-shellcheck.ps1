<# Ensures ShellCheck is available for local Bash linting. #>
param([switch]$Audit)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$packageId = Get-DevSetupValue $config "advanced.shellcheck.wingetPackageId" "koalaman.shellcheck"

function Find-ShellCheckExecutable {
    $command = Get-Command shellcheck.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if ($command) { return $command }

    $configuredPaths = Get-DevSetupValue $config "advanced.shellcheck.windowsSearchPaths" @(
        "%LOCALAPPDATA%\Microsoft\WinGet\Packages\{wingetPackageId}_*\shellcheck.exe"
    )
    $configuredPaths |
        ForEach-Object { Expand-DevSetupPath ($_ -replace '\{wingetPackageId\}', $packageId) } |
        ForEach-Object { Get-ChildItem $_ -File -ErrorAction SilentlyContinue } |
        Select-Object -First 1 -ExpandProperty FullName
}

$shellCheck = Find-ShellCheckExecutable
if ($Audit) {
    if ($shellCheck) { Write-DevSetupStatus found "ShellCheck" "$(& $shellCheck --version | Select-Object -First 1) at $shellCheck" }
    elseif (Get-Command winget.exe -ErrorAction SilentlyContinue) { Write-DevSetupStatus install "ShellCheck" "would install $packageId via winget" }
    else { Write-DevSetupStatus warn "ShellCheck" "missing and winget is unavailable" }
    return
}

if (-not $shellCheck) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw "ShellCheck is unavailable and winget is not installed. Install it from https://www.shellcheck.net/." }
    Write-DevSetupStatus install "ShellCheck" "installing $packageId via winget (per-user, no admin, no GUI)"
    & winget.exe install --id $packageId -e --scope user --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "winget failed to install $packageId (exit code $LASTEXITCODE)." }
    $env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable("Path", "Machine"), [Environment]::GetEnvironmentVariable("Path", "User")) | Where-Object { $_ }) -join ";"
    $shellCheck = Find-ShellCheckExecutable
}
if (-not $shellCheck) { throw "ShellCheck setup completed but shellcheck.exe was not found. Open a new terminal and run setup again." }
$shellCheckDirectory = Split-Path -Parent $shellCheck
$env:Path = "$shellCheckDirectory;$env:Path"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$shellCheckDirectory*") {
    [Environment]::SetEnvironmentVariable("Path", "$shellCheckDirectory;$userPath", "User")
}
Write-DevSetupStatus found "ShellCheck" "$(& $shellCheck --version | Select-Object -First 1) at $shellCheck"