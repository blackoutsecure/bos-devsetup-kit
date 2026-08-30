<#
.SYNOPSIS
    Sets up Git, Node.js, Python, and VS Code settings without admin rights or GUI installers.
.DESCRIPTION
    Bootstraps user-local PortableGit when needed (which also configures the
    credential helper), installs Node.js and Python, and applies VS Code
    settings last. Python setup runs natively in PowerShell rather than through
    Git Bash, since PortableGit's minimal Bash/coreutils are not a reliable
    environment for running installer scripts.

    Every tunable lives in config/dev-setup.config.json. Parameters here override
    it for a single run. The final step runs src/configure-vscode.py, which stores
    the syncable VS Code settings including Dev Containers defaults. Dev containers
    stay opt-in; nothing is containerized by this script.
#>
param(
    [string]$GitInstallDir,
    [string]$PythonVersion,
    [switch]$SkipVSCodeSettings,
    [switch]$Audit
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "src\config.ps1")
$configPath = $DevSetupConfigPath
$config = Get-DevSetupConfig $configPath
$scripts = Join-Path $PSScriptRoot "src\scripts"

if (-not $GitInstallDir) {
    $GitInstallDir = Expand-DevSetupPath (Get-DevSetupValue $config "user.git.installDir" (
        Get-DevSetupValue $config "advanced.git.defaultInstallDir" "$env:USERPROFILE\PortableGit"))
}
if (-not $PythonVersion) {
    $PythonVersion = Get-DevSetupValue $config "user.python.version" "3.14"
}

$configureVSCode = (-not $SkipVSCodeSettings) -and (Get-DevSetupValue $config "user.install.vscodeSettings" $true)
$gitExe = $null
$pythonExe = $null

if ($Audit) {
    Write-Host "Auditing (detect only - nothing will be installed or changed):"
} else {
    Write-Host "Running setup (each step is skipped when already satisfied):"
}

if (Get-DevSetupValue $config "user.install.git" $true) {
    $gitExe = & (Join-Path $scripts "install-portable-git.ps1") -InstallDir $GitInstallDir -ConfigureVSCode:$configureVSCode -PrintPath:$configureVSCode -Audit:$Audit |
        Select-Object -Last 1
} else {
    Write-DevSetupStatus skip "Git" "user.install.git is false"
}

if (Get-DevSetupValue $config "user.install.node" $true) {
    & (Join-Path $scripts "install-node.ps1") -Audit:$Audit
} else {
    Write-DevSetupStatus skip "Node.js" "user.install.node is false"
}

if (Get-DevSetupValue $config "user.install.python" $true) {
    # install-python.ps1 emits the resolved interpreter path as its last output.
    $pythonExe = & (Join-Path $scripts "install-python.ps1") -PythonVersion $PythonVersion -ConfigureVSCode:$configureVSCode -Audit:$Audit |
        Select-Object -Last 1
} else {
    Write-DevSetupStatus skip "Python" "user.install.python is false"
}

if (-not $configureVSCode) {
    $reason = if ($SkipVSCodeSettings) { "-SkipVSCodeSettings was passed" } else { "user.install.vscodeSettings is false" }
    Write-DevSetupStatus skip "vscode" $reason
}

if ($configureVSCode) {
    if (-not ($pythonExe -and (Test-Path $pythonExe))) {
        # install-python.ps1 updates the user-level PATH, which the current session
        # does not inherit, so rebuild $env:Path before looking for the interpreter.
        $env:Path = ((
            [Environment]::GetEnvironmentVariable("Path", "Machine"),
            [Environment]::GetEnvironmentVariable("Path", "User")
        ) | Where-Object { $_ }) -join ";"
        $pythonExe = Get-Command python.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.Source -notlike "*\Microsoft\WindowsApps\*" } |
            Select-Object -First 1 -ExpandProperty Source
    }

    if ($pythonExe) {
        $arguments = @((Join-Path $PSScriptRoot "src\configure-vscode.py"), "--config", $configPath, "--python-path", $pythonExe)
        if ($gitExe -and (Test-Path $gitExe)) { $arguments += @("--git-path", $gitExe) }
        if ($Audit) { $arguments += "--dry-run" }
        & $pythonExe $arguments
    } else {
        Write-DevSetupStatus warn "vscode" "Python not on PATH; run src/configure-vscode.py manually from a new terminal"
    }
}

Write-Host ""
if ($Audit) {
    Write-Host "Audit complete. Nothing was installed or changed. Re-run without -Audit to apply."
} else {
    Write-Host "Setup complete. WSL was not installed or invoked."
    if ($configureVSCode) {
        Write-Host "VS Code settings were validated; GitHub Settings Sync was requested when already enabled."
    }
}
