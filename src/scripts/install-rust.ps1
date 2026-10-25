<#
.SYNOPSIS
    Ensures rustup, stable Rust, and editor components are available per user.
.DESCRIPTION
    Preserves existing default toolchains. Audit never installs or compiles.
    Uninstall deliberately leaves shared Rust toolchains and Cargo packages alone.
#>
param([switch]$Audit, [switch]$Uninstall, [switch]$CheckUpgrades)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig

if ($Uninstall) {
    Write-DevSetupStatus skip "Rust" "shared rustup toolchains and Cargo packages are preserved; remove manually with rustup self uninstall if intended"
    return
}

$cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE ".cargo" }
$cargoBin = Join-Path $cargoHome "bin"
$packageId = Get-DevSetupValue $config "advanced.rust.wingetPackageId" "Rustlang.Rustup"
$find = {
    $command = Get-Command rustup.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $cargoBin "rustup.exe"
    if (Test-Path $candidate) { return $candidate }
}
$fallback = {
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    $hostTriple = switch ($architecture) {
        "AMD64" { "x86_64-pc-windows-msvc" }
        "ARM64" { "aarch64-pc-windows-msvc" }
        "x86" { "i686-pc-windows-msvc" }
        default { throw "Unsupported Rust bootstrap architecture: $architecture" }
    }
    $baseUrl = Get-DevSetupValue $config "advanced.rust.bootstrapBaseUrl" "https://static.rust-lang.org/rustup/dist"
    $url = "$baseUrl/$hostTriple/rustup-init.exe"
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("devsetup-rustup-{0}" -f [guid]::NewGuid())
    New-Item -Path $stage -ItemType Directory | Out-Null
    try {
        $installer = Join-Path $stage "rustup-init.exe"
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing -TimeoutSec 120
        $digest = (Invoke-WebRequest -Uri "$url.sha256" -UseBasicParsing -TimeoutSec 120).Content
        if ($digest -is [byte[]]) { $digest = [Text.Encoding]::UTF8.GetString($digest) }
        if ("$digest" -notmatch '^\s*([a-fA-F0-9]{64})(?:\s|$)') { throw "Invalid official rustup SHA256 response" }
        $expected = $Matches[1]
        if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $expected) { throw "Rustup SHA256 verification failed" }
        Write-DevSetupStatus install "rustup" "running official SHA256-verified user installer; no toolchain or linker default override"
        & $installer -y --no-modify-path --default-toolchain none --profile minimal
        if ($LASTEXITCODE -ne 0) { throw "Rustup installer failed (exit $LASTEXITCODE)" }
        & $find
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
$rustup = Install-DevSetupWingetTool -Component "rustup" -PackageId $packageId -Find $find -Audit:$Audit -CheckUpgrades:$CheckUpgrades `
    -FallbackInstall $fallback `
    -FallbackDescription "the official SHA256-verified user-local rustup installer" `
    -ManualInstallHint "Install rustup per-user from https://rustup.rs/; Windows native compilation also needs a working linker."
if (-not $rustup) {
    Write-DevSetupStatus install "Rust" "would provision stable with rustfmt, clippy, rust-src after rustup installation"
    Write-DevSetupStatus skip "Rust build" "linker readiness is unverified; audit does not compile or run code"
    return
}

function Invoke-Rustup {
    param([string[]]$Arguments)
    & $rustup @Arguments
    if ($LASTEXITCODE -ne 0) { throw "rustup $($Arguments -join ' ') failed (exit $LASTEXITCODE)" }
}

$toolchains = @(Invoke-Rustup -Arguments @("toolchain", "list"))
$hasStable = @($toolchains | Where-Object { $_ -match '^stable(?:-|\s|$)' }).Count -gt 0
if (-not $hasStable) {
    if ($Audit) {
        Write-DevSetupStatus install "Rust stable" "would install stable with rustfmt, clippy, rust-src; existing defaults remain unchanged"
        Write-DevSetupStatus skip "Rust build" "linker readiness is unverified; audit does not compile or run code"
        return
    }
    Write-DevSetupStatus install "Rust stable" "installing stable with minimal profile"
    Invoke-Rustup -Arguments @("toolchain", "install", "stable", "--profile", "minimal") | Out-Host
}
if (@($toolchains | Where-Object { $_ -match '\([^)]*\bdefault\b[^)]*\)' }).Count -eq 0) {
    if ($Audit) {
        Write-DevSetupStatus install "Rust default" "would select stable because no default toolchain exists"
    } else {
        Write-DevSetupStatus install "Rust default" "selecting stable because no default toolchain exists"
        Invoke-Rustup -Arguments @("default", "stable") | Out-Host
    }
}

$installed = @(Invoke-Rustup -Arguments @("component", "list", "--installed", "--toolchain", "stable"))
foreach ($component in @("rustfmt", "clippy", "rust-src")) {
    if (@($installed | Where-Object { $_ -eq $component -or $_ -like "$component-*" }).Count -gt 0) {
        Write-DevSetupStatus found "Rust $component" "installed for stable"
    } elseif ($Audit) {
        Write-DevSetupStatus install "Rust $component" "would add component to stable"
    } else {
        Invoke-Rustup -Arguments @("component", "add", "--toolchain", "stable", $component) | Out-Host
        Write-DevSetupStatus install "Rust $component" "added to stable"
    }
}
foreach ($tool in @("rustc", "cargo")) {
    $version = Invoke-Rustup -Arguments @("run", "stable", $tool, "--version")
    Write-DevSetupStatus found "Rust $tool" "$version"
}
if ($CheckUpgrades) { Invoke-Rustup -Arguments @("check") | Out-Host }

if ($Audit) {
    Write-DevSetupStatus skip "Rust build" "linker readiness is unverified; audit does not compile or run code"
    return
}

Add-DevSetupUserPath $cargoBin
Update-DevSetupSessionPath
$probe = Join-Path ([IO.Path]::GetTempPath()) ("devsetup-rust-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $probe | Out-Null
try {
    $source = Join-Path $probe "probe.rs"
    $binary = Join-Path $probe "probe.exe"
    Set-Content -Path $source -Value 'fn main() { println!("rust-ready"); }' -Encoding ASCII
    try {
        $output = & $rustup run stable rustc --edition 2021 --crate-name devsetup_probe $source -o $binary 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $output.Trim() }
        $output = & $binary 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or $output.Trim() -ne "rust-ready") { throw "compiled probe did not run successfully: $output" }
        Write-DevSetupStatus found "Rust build" "stable compiled, linked, and ran a native executable"
    } catch {
        Write-DevSetupStatus warn "Rust build" "toolchain installed but native build/run failed: $($_.Exception.Message). MSVC needs C++ Build Tools; GNU needs compatible MinGW tools. No admin install or global linker override was attempted."
    }
} finally {
    Remove-Item -LiteralPath $probe -Recurse -Force
}
