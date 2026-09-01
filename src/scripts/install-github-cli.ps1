<# Ensures GitHub CLI is available for repository and PR automation. #>
param([switch]$Audit, [switch]$Uninstall, [switch]$CheckUpgrades, [switch]$AllowAdminInstall)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$packageId = Get-DevSetupValue $config "advanced.githubCli.wingetPackageId" "GitHub.cli"

if ($Uninstall) {
    Uninstall-DevSetupWingetTool -Component "GitHub CLI" -PackageId $packageId -Audit:$Audit
    return
}

$find = {
    Find-DevSetupWingetExecutable $config "gh.exe" "advanced.githubCli.windowsSearchPaths" $packageId @(
        "%LOCALAPPDATA%\Microsoft\WinGet\Packages\{wingetPackageId}_*\gh.exe",
        "%LOCALAPPDATA%\Microsoft\WinGet\Packages\{wingetPackageId}_*\bin\gh.exe",
        "%LOCALAPPDATA%\Microsoft\WinGet\Packages\{wingetPackageId}_*\*\bin\gh.exe",
        "%LOCALAPPDATA%\Programs\GitHub CLI\gh.exe",
        "%LOCALAPPDATA%\Programs\GitHub CLI\bin\gh.exe",
        "%ProgramFiles%\GitHub CLI\gh.exe",
        "%ProgramFiles%\GitHub CLI\bin\gh.exe"
    )
}

$gh = Install-DevSetupWingetTool -Component "GitHub CLI" -PackageId $packageId -Find $find -Audit:$Audit -CheckUpgrades:$CheckUpgrades `
    -AllowAdminInstall:$AllowAdminInstall -ManualInstallHint "Install GitHub CLI from https://cli.github.com/." |
    Select-Object -Last 1

if ($Audit) { return $gh }

$ghDirectory = Split-Path -Parent $gh
$env:Path = "$ghDirectory;$env:Path"
Add-DevSetupUserPath $ghDirectory -Prepend
return $gh
