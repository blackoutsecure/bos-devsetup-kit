<# Ensures PHP is available for VS Code's built-in PHP validator. #>
param([switch]$Audit)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$packageId = Get-DevSetupValue $config "advanced.php.wingetPackageId" "PHP.PHP"
$php = Get-Command php.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source

if ($Audit) {
    if ($php) { Write-DevSetupStatus found "PHP" "$(& $php --version | Select-Object -First 1) at $php" }
    elseif (Get-Command winget.exe -ErrorAction SilentlyContinue) { Write-DevSetupStatus install "PHP" "would install $packageId via winget" }
    else { Write-DevSetupStatus warn "PHP" "missing and winget is unavailable" }
    return
}

if (-not $php) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw "PHP is unavailable and winget is not installed. Install PHP from https://www.php.net/downloads.php." }
    Write-DevSetupStatus install "PHP" "installing $packageId via winget (per-user, no admin, no GUI)"
    & winget.exe install --id $packageId -e --scope user --accept-package-agreements --accept-source-agreements --silent
    $php = Get-Command php.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
}
if (-not $php) { throw "PHP setup completed but php.exe was not found. Open a new terminal and run setup again." }
Write-DevSetupStatus found "PHP" "$(& $php --version | Select-Object -First 1) at $php"
$php
