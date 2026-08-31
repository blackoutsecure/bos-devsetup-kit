<# Ensures PowerShell 7 is available for VS Code's PowerShell extension. #>
param([switch]$Audit, [switch]$Uninstall, [switch]$CheckUpgrades)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$packageId = Get-DevSetupValue $config "advanced.powershell.wingetPackageId" "Microsoft.PowerShell"

if ($Uninstall) {
    Uninstall-DevSetupWingetTool -Component "PowerShell" -PackageId $packageId -Audit:$Audit
    return
}

$find = { Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source }

Install-DevSetupWingetTool -Component "PowerShell" -PackageId $packageId -Find $find -Audit:$Audit -CheckUpgrades:$CheckUpgrades `
    -ManualInstallHint "Install it from https://learn.microsoft.com/powershell/."
