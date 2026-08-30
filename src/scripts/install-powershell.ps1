<# Ensures PowerShell 7 is available for VS Code's PowerShell extension. #>
param([switch]$Audit)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$packageId = Get-DevSetupValue $config "advanced.powershell.wingetPackageId" "Microsoft.PowerShell"
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source

if ($Audit) {
    if ($pwsh) { Write-DevSetupStatus found "PowerShell" "$(& $pwsh --version) at $pwsh" }
    elseif (Get-Command winget.exe -ErrorAction SilentlyContinue) { Write-DevSetupStatus install "PowerShell" "would install $packageId via winget" }
    else { Write-DevSetupStatus warn "PowerShell" "missing and winget is unavailable" }
    return
}

if (-not $pwsh) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw "PowerShell is unavailable and winget is not installed. Install it from https://learn.microsoft.com/powershell/." }
    Write-DevSetupStatus install "PowerShell" "installing $packageId via winget (per-user, no admin, no GUI)"
    & winget.exe install --id $packageId -e --scope user --accept-package-agreements --accept-source-agreements --silent
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
}
if (-not $pwsh) { throw "PowerShell setup completed but pwsh.exe was not found. Open a new terminal and run setup again." }
Write-DevSetupStatus found "PowerShell" "$(& $pwsh --version) at $pwsh"
$pwsh
