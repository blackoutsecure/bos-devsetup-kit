<# Ensures GPG is available for Git commit/tag signing. #>
param([switch]$Audit, [switch]$Uninstall, [switch]$CheckUpgrades)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$packageId = Get-DevSetupValue $config "advanced.gpg.wingetPackageId" "GnuPG.Gpg4win"

if ($Uninstall) {
    Uninstall-DevSetupWingetTool -Component "GPG" -PackageId $packageId -Audit:$Audit
    return
}

$find = {
    Find-DevSetupWingetExecutable $config "gpg.exe" "advanced.gpg.windowsSearchPaths" $packageId @(
        "%ProgramFiles(x86)%\GnuPG\bin\gpg.exe",
        "%ProgramFiles%\GnuPG\bin\gpg.exe",
        "%LOCALAPPDATA%\Microsoft\WinGet\Packages\{wingetPackageId}_*\GnuPG\bin\gpg.exe"
    )
}

$gpg = Install-DevSetupWingetTool -Component "GPG" -PackageId $packageId -Find $find -Audit:$Audit -CheckUpgrades:$CheckUpgrades `
    -ManualInstallHint "Gpg4win's WinGet package does not support a per-user-only install on every machine. Run 'winget install --id $packageId -e' yourself and accept any elevation prompt, or install manually from https://www.gpg4win.org/." |
    Select-Object -Last 1

if ($Audit) { return }

# Gpg4win's installer usually updates PATH itself, but per-user winget installs don't always
# take effect in the current session, so make gpg usable here the same way ShellCheck is.
$gpgDirectory = Split-Path -Parent $gpg
$env:Path = "$gpgDirectory;$env:Path"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$gpgDirectory*") {
    [Environment]::SetEnvironmentVariable("Path", "$gpgDirectory;$userPath", "User")
}
