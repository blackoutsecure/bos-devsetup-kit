import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which("powershell") if os.name == "nt" else None
BASH = shutil.which("bash")


class RustInstallerTests(unittest.TestCase):
    def fixture(self, root):
        scripts = root / "src" / "scripts"
        scripts.mkdir(parents=True)
        for name in ("install-rust.ps1", "install-rust.sh"):
            shutil.copyfile(ROOT / "src" / "scripts" / name, scripts / name)
        (root / "components").write_text("rustfmt-host\n", encoding="utf-8")
        return scripts

    @unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
    def test_windows_bootstrap_verifies_digest_before_execution(self):
        for bad_hash in (False, True):
            with self.subTest(bad_hash=bad_hash), tempfile.TemporaryDirectory() as temp_dir:
                root = Path(temp_dir)
                scripts = self.fixture(root)
                env = {
                    **os.environ, "FIXTURE": str(root),
                    "CARGO_HOME": str(root / "cargo"), "NO_COLOR": "1",
                    "BAD_HASH": "1" if bad_hash else "0",
                }
                env = {key: value for key, value in env.items() if key.lower() != "psmodulepath"}
                fixture_source = root / "build-fixture.ps1"
                fixture_source.write_text(r"""
Add-Type -TypeDefinition 'public class Bootstrap { public static void Main(string[] args) { System.IO.File.WriteAllText(System.IO.Path.Combine(System.Environment.GetEnvironmentVariable("FIXTURE"), "executed"), string.Join(" ", args)); } }' -OutputAssembly (Join-Path $env:FIXTURE 'bootstrap.exe') -OutputType ConsoleApplication
""", encoding="utf-8")
                built = subprocess.run(
                    [POWERSHELL, "-NoProfile", "-NonInteractive", "-File", str(fixture_source)],
                    env=env, capture_output=True, text=True, timeout=30, check=False,
                )
                self.assertEqual(built.returncode, 0, built.stderr)
                (root / "src" / "config.ps1").write_text(r"""
. 'REAL_MODULE'
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    if ($OutFile) { Copy-Item (Join-Path $env:FIXTURE 'bootstrap.exe') $OutFile }
    else {
        $digest = (Get-FileHash (Join-Path $env:FIXTURE 'bootstrap.exe') -Algorithm SHA256).Hash
        if ($env:BAD_HASH -eq '1') { $digest = '0' * 64 }
        return [pscustomobject]@{Content=[Text.Encoding]::UTF8.GetBytes("$digest rustup-init.exe")}
    }
}
function Install-DevSetupWingetTool {
    param($Component, $PackageId, $Find, [switch]$Audit, [switch]$CheckUpgrades, $ManualInstallHint, $FallbackInstall, $FallbackDescription)
    & $FallbackInstall | Out-Null
    Write-Host 'PASS: verified bootstrap executed'
    exit 0
}
""".replace("REAL_MODULE", str(ROOT / "src" / "config.ps1").replace("'", "''")), encoding="utf-8")
                result = subprocess.run(
                    [POWERSHELL, "-NoProfile", "-NonInteractive", "-File",
                     str(scripts / "install-rust.ps1")],
                    env=env, capture_output=True, text=True, timeout=30, check=False,
                )
                if bad_hash:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("SHA256 verification failed", result.stderr)
                    self.assertFalse((root / "executed").exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertIn("PASS: verified bootstrap executed", result.stdout)
                    self.assertEqual(
                        (root / "executed").read_text(),
                        "-y --no-modify-path --default-toolchain none --profile minimal",
                    )

    @unittest.skipUnless(POWERSHELL, "Windows PowerShell is required")
    def test_windows_audit_repair_idempotence_and_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            scripts = self.fixture(root)
            (root / "src" / "config.ps1").write_text(r"""
. 'REAL_MODULE'
function Install-DevSetupWingetTool {
    param($Component, $PackageId, $Find, [switch]$Audit, [switch]$CheckUpgrades, $ManualInstallHint, $FallbackInstall, $FallbackDescription)
    return (Join-Path $env:FIXTURE 'rustup.ps1')
}
function Add-DevSetupUserPath { param($Directory); Write-Host '[found] PATH fixture' }
function Update-DevSetupSessionPath {}
""".replace("REAL_MODULE", str(ROOT / "src" / "config.ps1").replace("'", "''")), encoding="utf-8")
            (root / "rustup.ps1").write_text(r"""
$arguments = @($args)
Add-Content (Join-Path $env:FIXTURE 'calls') ($arguments -join ' ')
switch ($arguments[0]) {
    'toolchain' {
        if ($arguments[1] -eq 'install') { Remove-Item (Join-Path $env:FIXTURE 'no-stable'); break }
        if (-not (Test-Path (Join-Path $env:FIXTURE 'no-stable'))) { 'stable-host' }
        '1.99.1-host (active, default)'
    }
    'component' {
        if ($arguments[1] -eq 'list') { Get-Content (Join-Path $env:FIXTURE 'components') }
        else { Add-Content (Join-Path $env:FIXTURE 'components') $arguments[-1] }
    }
    'default' { throw 'Must not replace an existing default' }
    'run' {
        if ($arguments[-1] -eq '--version') { "$($arguments[2]) fixture" }
        else {
            if (Test-Path (Join-Path $env:FIXTURE 'fail')) { Write-Output 'fixture linker missing'; exit 1 }
            $destination = $arguments[-1]
            Copy-Item (Join-Path $env:FIXTURE 'ready.exe') $destination
        }
    }
    'check' { 'stable is current' }
    default { throw "Unexpected command: $arguments" }
}
exit 0
""", encoding="utf-8")
            env = {**os.environ, "FIXTURE": str(root), "NO_COLOR": "1"}
            env = {key: value for key, value in env.items() if key.lower() != "psmodulepath"}
            # Build only a disposable fixture executable, never a toolchain or machine install.
            fixture_source = root / "build-fixture.ps1"
            fixture_source.write_text(r"""
Add-Type -TypeDefinition 'public class Ready { public static void Main() { System.Console.WriteLine("rust-ready"); } }' -OutputAssembly (Join-Path $env:FIXTURE 'ready.exe') -OutputType ConsoleApplication
""", encoding="utf-8")
            built = subprocess.run(
                [POWERSHELL, "-NoProfile", "-NonInteractive", "-File", str(fixture_source)],
                env=env, capture_output=True, text=True, timeout=30, check=False,
            )
            self.assertEqual(built.returncode, 0, built.stderr)

            def run(*args):
                result = subprocess.run(
                    [POWERSHELL, "-NoProfile", "-NonInteractive", "-File",
                     str(scripts / "install-rust.ps1"), *args],
                    env=env, capture_output=True, text=True, timeout=30, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout

            original = (root / "components").read_bytes()
            audit = run("-Audit", "-CheckUpgrades")
            self.assertIn("would add", audit)
            self.assertIn("readiness is unverified", audit)
            self.assertEqual((root / "components").read_bytes(), original)
            calls = (root / "calls").read_text()
            self.assertNotIn("component add", calls)
            self.assertNotIn("probe.rs", calls)
            self.assertIn("compiled, linked, and ran", run())
            second = run()
            self.assertNotIn("[install]", second)
            self.assertNotIn("[warn]", second)
            (root / "no-stable").touch()
            self.assertIn("would install stable", run("-Audit"))
            self.assertTrue((root / "no-stable").exists())
            self.assertIn("installing stable", run())
            self.assertFalse((root / "no-stable").exists())
            (root / "fail").touch()
            self.assertIn("native build/run failed", run())
            self.assertIn("preserved", run("-Uninstall"))

    @unittest.skipUnless(BASH, "Bash is required")
    def test_bash_audit_repair_idempotence_and_failure(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            self.fixture(root)
            (root / "src" / "config.sh").write_text("""
devsetup_config() { printf '%s' "$2"; }
devsetup_status() { printf '[%s] %s %s\\n' "$1" "$2" "$3"; }
devsetup_homebrew_path() { return 1; }
""", encoding="utf-8")
            (root / "rustup").write_text("""#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$HOME/calls"
case "$1" in
toolchain)
    if [[ "$2" == install ]]; then rm "$HOME/no-stable"
    else
        if [[ ! -f "$HOME/no-stable" ]]; then echo 'stable-host'; fi
        echo '1.99.1-host (active, default)'
    fi ;;
component)
    if [[ "$2" == list ]]; then cat "$HOME/components"
    else printf '%s\\n' "${@: -1}" >> "$HOME/components"; fi ;;
default) echo 'must preserve default' >&2; exit 1 ;;
run)
    if [[ "${@: -1}" == --version ]]; then echo "$3 fixture"
    elif [[ -f "$HOME/fail" ]]; then echo 'fixture linker missing' >&2; exit 1
    else
        printf '#!/usr/bin/env bash\\necho rust-ready\\n' > "${@: -1}"
        chmod +x "${@: -1}"
    fi ;;
check) echo 'stable is current' ;;
*) exit 2 ;;
esac
""", encoding="utf-8")
            env = {**os.environ, "TEST_HOME": str(root), "NO_COLOR": "1"}
            setup = """
if command -v cygpath >/dev/null 2>&1; then
    export HOME="$(cygpath -u "$TEST_HOME")"
else
    export HOME="$TEST_HOME"
fi
export PATH="$HOME:$PATH"
uname() { echo Linux; }
export -f uname
chmod +x "$HOME/rustup"
bash src/scripts/install-rust.sh "$@"
"""

            def run(*args):
                result = subprocess.run(
                    [BASH, "-c", setup, "fixture", *args], cwd=root, env=env,
                    capture_output=True, text=True, timeout=30, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout

            original = (root / "components").read_bytes()
            audit = run("--audit", "--check-upgrades")
            self.assertIn("would add", audit)
            self.assertEqual((root / "components").read_bytes(), original)
            self.assertFalse((root / ".profile").exists())
            self.assertNotIn("component add", (root / "calls").read_text())
            self.assertIn("compiled, linked, and ran", run())
            before = (root / ".profile").read_bytes()
            second = run()
            self.assertNotIn("[install]", second)
            self.assertNotIn("[warn]", second)
            self.assertEqual((root / ".profile").read_bytes(), before)
            (root / "no-stable").touch()
            self.assertIn("would install stable", run("--audit"))
            self.assertTrue((root / "no-stable").exists())
            self.assertIn("installing stable", run())
            self.assertFalse((root / "no-stable").exists())
            (root / "fail").touch()
            self.assertIn("native build/run failed", run())
            self.assertIn("preserved", run("--uninstall"))

    def test_all_entrypoint_modes_are_wired(self):
        for name, installer in (("setup.ps1", "install-rust.ps1"), ("setup.sh", "install-rust.sh")):
            text = (ROOT / name).read_text()
            self.assertEqual(text.count(installer), 3)
            self.assertIn("user.install.rust is false", text)
        config = json.loads((ROOT / "config" / "dev-setup.config.json").read_text())
        self.assertEqual(config["advanced"]["rust"]["wingetPackageId"], "Rustlang.Rustup")
        self.assertEqual(config["advanced"]["rust"]["homebrewFormula"], "rustup")


if __name__ == "__main__":
    unittest.main()
