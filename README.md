# Blackout Secure Dev Setup Kit

[![Made by BlackoutSecure](https://img.shields.io/badge/made%20by-BlackoutSecure-1f1f1f)](https://github.com/blackoutsecure)

Cross-platform developer environment setup for machines **without local admin rights**.

Installs Git, Node.js, Python, PHP, and PowerShell per-user, then applies VS Code settings that follow you through
Settings Sync. Every step auto-detects what is already present and skips it, reporting each decision
in the terminal. Nothing requires WSL, sudo, or a GUI installer.

- **Audit first.** `setup.ps1 -Audit` / `setup.sh --audit` reports what would change and writes nothing.
- **One config.** Every tunable lives in [`config/dev-setup.config.json`](config/dev-setup.config.json).
- **Idempotent.** Re-running is safe; values are compared before they are written.
- **Color-coded.** Each line is tagged `[found]` (green), `[install]` (cyan), `[warn]` (yellow), or
  `[skip]` (grey) — identically across PowerShell, bash, and the Python VS Code applier. Colors are
  suppressed for `NO_COLOR`, non-TTY output, and are always on under `GITHUB_ACTIONS`.

## Requirements

| Platform        | Needs                                                                                                     |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| Windows         | PowerShell 5.1+. `winget` for Node.js/Python (falls back to `uv` for Python).                             |
| macOS           | Xcode Command Line Tools for Git. Homebrew for Node.js.                                                   |
| Linux           | Homebrew is installed under `$HOME` automatically if missing.                                             |
| Platform        | Needs                                                                                                     |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| Windows         | PowerShell 5.1+. `winget` for Node.js, Python, PHP, and PowerShell 7 (falls back to `uv` for Python).     |
| macOS           | Xcode Command Line Tools for Git. Homebrew for Node.js, PHP, and PowerShell.                              |
| Ubuntu / Debian | Homebrew is installed under `$HOME` automatically if missing; used for Git, Node.js, PHP, and PowerShell. |

No administrator or root access is required at any point. WSL is never installed or invoked.

## Quick start

Windows — `setup.cmd` is the bootloader; it runs `setup.ps1`:

```powershell
.\setup.cmd
```

macOS / Linux:

```bash
chmod +x setup.sh
./setup.sh
```

Run an audit first to see what would happen:

```powershell
.\setup.ps1 -Audit
```

```bash
./setup.sh --audit
```

Audit mode installs nothing, writes no files, and does not touch git config or `PATH`.

### Repository checks

This kit installs machine and editor prerequisites; repositories keep their own pinned Node and
Python tooling. From a repository root, use its declared check command. The common patterns in
this organization are:

```bash
npm run check
```

```bash
python -m pytest -q
```

Use the repository's `package.json`, `pyproject.toml`, or contributor guide as the authority when
it differs. Do not install project linters or test runners globally. For Python repositories, create
or select the repository virtual environment first; this kit recommends `.venv` and configures VS
Code to discourage global package installs.

### Options

| Option                  | Applies to                  | Effect                                      |
| ----------------------- | --------------------------- | ------------------------------------------- |
| `-Audit` / `--audit`    | runners and every installer | Detect and report only.                     |
| `-SkipVSCodeSettings`   | `setup.ps1`                 | Leave editor settings alone for one run.    |
| `-GitInstallDir <path>` | `setup.ps1`                 | Override `user.git.installDir` for one run. |
| `-PythonVersion <x.y>`  | `setup.ps1`                 | Override `user.python.version` for one run. |

## Audit output

```text
Auditing (detect only - nothing will be installed or changed):
  [found]   Git      git version 2.51.0 at C:\Program Files\Git\cmd\git.exe
  [install] git cfg  would set credential.helper, credential.credentialStore, credential.guiPrompt
  [warn]    identity not set; fill user.git.userName / user.git.userEmail
  [found]   Node.js  v22.11.0 at C:\Program Files\nodejs\node.exe
  [install] Python   would install Python.Python.3.14 via winget
  [install] vscode   would set 5 setting(s) in <user-profile>\Code\User
             - python.globalModuleInstallation
             - dev.containers.defaultExtensions
             - git.path
             - python.defaultInterpreterPath
             - python.terminal.activateEnvironment
  [skip]    validate dry-run; files were not changed
  [install] sync     would request Settings Sync (stable)

Audit complete. Nothing was installed or changed. Re-run without -Audit to apply.
```

The same vocabulary is used during a real run:

| Status      | Meaning                                                        |
| ----------- | -------------------------------------------------------------- |
| `[found]`   | Already present and correct. Nothing was done.                 |
| `[install]` | Something was changed or installed.                            |
| `[skip]`    | Disabled in config, or not applicable on this platform.        |
| `[warn]`    | Continued, but the result is degraded or needs your attention. |

## Layout

```text
setup.cmd     Windows bootloader -> setup.ps1
setup.ps1     Windows runner
setup.sh      macOS / Linux runner
config/       the single config file you edit
src/          all implementation
src/scripts/  one installer per tool, each runnable on its own
.github/      repo-specific automation config, Dependabot, and CODEOWNERS
```

| Path                                | Contents                                                                                         |
| ----------------------------------- | ------------------------------------------------------------------------------------------------ |
| root                                | The entrypoints you actually type. Nothing else.                                                 |
| `config/dev-setup.config.json`      | Single source of truth for every setting. Kept at the top level because it is the file you edit. |
| `src/config.ps1`, `src/config.sh`   | Config loader, dotted-path lookup, status reporter, shared helpers.                              |
| `src/configure-vscode.py`           | Cross-platform VS Code settings, extensions, and MCP applier.                                    |
| `src/scripts/install-*.{ps1,sh}`    | Per-tool install steps invoked by the runners.                                                   |
| `.github/bos-universal-config.json` | Repo-specific Blackout Secure automation config.                                                 |
| `.github/dependabot.yml`            | Repo-specific dependency-update config.                                                          |
| `.github/CODEOWNERS`                | Repo-specific review ownership.                                                                  |
| Path                                | Contents                                                                                         |
| ---------------------------------   | ------------------------------------------------------------------------------------------------ |
| root                                | The entrypoints you actually type. Nothing else.                                                 |
| `config/dev-setup.config.json`      | Single source of truth for every setting. Kept at the top level because it is the file you edit. |
| `src/config.ps1`, `src/config.sh`   | Config loader, dotted-path lookup, status reporter, shared helpers.                              |
| `src/configure-vscode.py`           | Cross-platform VS Code settings, extensions, and MCP applier.                                    |
| `src/scripts/install-*.{ps1,sh}`    | Per-tool install steps invoked by the runners.                                                   |

Every script resolves the repository root from its own location, so the runners and the individual
installers work from any working directory.

## Configuration reference

`config/dev-setup.config.json` has two top-level sections, read by `src/config.ps1` (PowerShell),
`src/config.sh` (bash), and `src/configure-vscode.py` (Python). A value is defined exactly once and
cannot drift between platforms.

Every lookup carries a built-in fallback. Deleting a key, leaving it `""`, or deleting the whole
config file degrades to the documented default rather than failing the run.

### User-editable recommendations

These are the supported knobs for routine use. They are safe to edit in a fork or personal copy.
These are the supported knobs for routine use. They are safe to edit in a fork or personal copy.
| Setting | Default | Purpose |
| ----------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `user.install.git` | `true` | Run the Git installer step. |
| `user.install.node` | `true` | Run the Node.js/npm step. |
| `user.install.python` | `true` | Run the Python step. |
| `user.install.php` | `true` | Run the PHP step. macOS/Linux use Homebrew; Windows uses WinGet. |
| `user.install.powershell` | `true` | Run the PowerShell 7 step. macOS/Linux use Homebrew; Windows uses WinGet. |
| `user.install.vscodeSettings` | `true` | Apply any VS Code settings at all. |
| `user.install.devcontainerDefaults` | `true` | Include the Dev Containers keys and snippet. |
| `user.install.mcpServers` | `true` | Reconcile MCP servers in `mcp.json`. |
| `user.git.installDir` | `""` | Windows PortableGit location. Empty uses `advanced.git.defaultInstallDir`. |
| `user.git.forcePortable` | `false` | Install PortableGit even when a system Git is on `PATH`. Left `false`, an existing Git is detected and the download is skipped. |
| `user.git.userName` | `""` | Applied via `git config --global user.name` when non-empty. |
| `user.git.userEmail` | `""` | Applied via `git config --global user.email` when non-empty. |
| `user.python.version` | `"3.14"` | Single source of truth for Windows winget and macOS/Linux `uv`. |
| `user.vscode.profiles` | `["stable","insiders"]` | Which VS Code profiles receive settings and extensions. |
| `user.vscode.settings` | curated set, see below | Settings merged verbatim into `settings.json`. Wins over everything else. |
| `user.vscode.extensions.manage` | `true` | Install/report extensions at all. |
| `user.vscode.extensions.install` | 17 extensions | Installed if missing, via the VS Code CLI. |
| `user.vscode.extensions.block` | 11 extensions | Never installed. Reported as `[warn]` if already present. |
| `user.vscode.extensions.uninstallBlocked` | `false` | When `true`, blocked extensions that are installed are removed instead of just reported. |
| `user.mcp.manage` | `true` | Reconcile MCP servers at all. |
| `user.mcp.servers` | 4 servers | Added to `mcp.json` if absent. Existing entries are never overwritten. |
| `user.mcp.inputs` | `[]` | `${input:id}` definitions. Required by any server that references one. |
| `user.mcp.block` | `[]` | Server IDs that should not be configured. Reported as `[warn]` if present. |
| `user.mcp.removeBlocked` | `false` | When `true`, blocked servers are deleted from `mcp.json` instead of reported. |
| `user.devcontainers.dockerAccess` | `"outside-of-docker"` | `outside-of-docker`, `in-docker`, or `none`. |
| `user.devcontainers.baseImage` | `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | Image used by the `devcontainer` snippet. |
| `user.devcontainers.remoteUser` | `"vscode"` | `remoteUser` emitted by the snippet. |
| `user.devcontainers.features` | common-utils, git, github-cli | Features always installed. The Docker feature is added from `dockerAccess`. |
| `user.devcontainers.extensions` | Copilot, PR, Actions, GitLens, EditorConfig, YAML, ShellCheck | Extensions always installed in a container. |
| `user.devcontainers.settings` | `copyGitConfig`, `gitCredentialHelperConfigLocation`, `cacheVolume`, `logLevel` | Remaining `dev.containers.*` keys. |

| Setting                                     | Default                                                                                                                                                                | Purpose                                                                                                                               |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `user.install.git`                          | `true`                                                                                                                                                                 | Run the Git installer step.                                                                                                           |
| `user.install.node`                         | `true`                                                                                                                                                                 | Run the Node.js/npm step.                                                                                                             |
| `user.install.python`                       | `true`                                                                                                                                                                 | Run the Python step.                                                                                                                  |
| `user.install.vscodeSettings`               | `true`                                                                                                                                                                 | Apply any VS Code settings at all.                                                                                                    |
| `user.install.devcontainerDefaults`         | `true`                                                                                                                                                                 | Include the Dev Containers keys and snippet.                                                                                          |
| `user.install.mcpServers`                   | `true`                                                                                                                                                                 | Reconcile MCP servers in `mcp.json`.                                                                                                  |
| `user.git.installDir`                       | `""`                                                                                                                                                                   | Windows PortableGit location. Empty uses `advanced.git.defaultInstallDir`.                                                            |
| `user.git.forcePortable`                    | `false`                                                                                                                                                                | Install PortableGit even when a system Git is on `PATH`. Left `false`, an existing Git is detected and the download is skipped.       |
| `user.git.userName`                         | `""`                                                                                                                                                                   | Applied via `git config --global user.name` when non-empty.                                                                           |
| `user.git.userEmail`                        | `""`                                                                                                                                                                   | Applied via `git config --global user.email` when non-empty.                                                                          |
| `user.python.version`                       | `"3.14"`                                                                                                                                                               | Single source of truth for Windows winget and macOS/Linux `uv`.                                                                       |
| `user.python.allowGlobalPackageInstalls`    | `false`                                                                                                                                                                | Written to VS Code as `python.globalModuleInstallation`; keep `false` to preserve the Python extension's virtual-environment warning. |
| `user.python.recommendedVirtualEnvironment` | `".venv"`                                                                                                                                                              | Documented environment folder recommendation for project-level dependencies.                                                          |
| `user.vscode.profiles`                      | `["stable","insiders"]`                                                                                                                                                | Which VS Code profiles receive settings and extensions.                                                                               |
| `user.vscode.settingsSync.syncAfterSetup`   | `true`                                                                                                                                                                 | After successful validation, request VS Code Settings Sync when it is already enabled.                                                |
| `user.vscode.settingsSync.requiredProvider` | `"github"`                                                                                                                                                             | Only request sync when the signed-in Settings Sync account provider matches this value.                                               |
| `user.vscode.settings`                      | curated set, see below                                                                                                                                                 | Settings merged verbatim into `settings.json`. Wins over everything else.                                                             |
| `user.vscode.extensions.manage`             | `true`                                                                                                                                                                 | Install/report extensions at all.                                                                                                     |
| `user.vscode.extensions.install`            | 17 extensions                                                                                                                                                          | Installed if missing, via the VS Code CLI.                                                                                            |
| `user.vscode.extensions.block`              | 11 extensions                                                                                                                                                          | Never installed. Reported as `[warn]` if already present.                                                                             |
| `user.vscode.extensions.uninstallBlocked`   | `false`                                                                                                                                                                | When `true`, blocked extensions that are installed are removed instead of just reported.                                              |
| `user.mcp.manage`                           | `true`                                                                                                                                                                 | Reconcile MCP servers at all.                                                                                                         |
| `user.mcp.servers`                          | 4 servers                                                                                                                                                              | Added to `mcp.json` if absent. Existing entries are never overwritten.                                                                |
| `user.mcp.inputs`                           | `[]`                                                                                                                                                                   | `${input:id}` definitions. Required by any server that references one.                                                                |
| `user.mcp.block`                            | `[]`                                                                                                                                                                   | Server IDs that should not be configured. Reported as `[warn]` if present.                                                            |
| `user.mcp.removeBlocked`                    | `false`                                                                                                                                                                | When `true`, blocked servers are deleted from `mcp.json` instead of reported.                                                         |
| `user.devcontainers.dockerAccess`           | `"outside-of-docker"`                                                                                                                                                  | `outside-of-docker`, `in-docker`, or `none`.                                                                                          |
| `user.devcontainers.baseImage`              | `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`                                                                                                                    | Image used by the `devcontainer` snippet.                                                                                             |
| `user.devcontainers.remoteUser`             | `"vscode"`                                                                                                                                                             | `remoteUser` emitted by the snippet.                                                                                                  |
| `user.devcontainers.features`               | common-utils, git, github-cli                                                                                                                                          | Features always installed. The Docker feature is added from `dockerAccess`.                                                           |
| `user.devcontainers.extensions`             | Copilot, PR, Actions, GitLens, EditorConfig, ESLint, Prettier, Ruff, Python, Pylance, debugpy, Markdownlint, Code Spell Checker, Markdown All in One, YAML, ShellCheck | Extensions always installed in a container.                                                                                           |
| `user.devcontainers.settings`               | `copyGitConfig`, `gitCredentialHelperConfigLocation`, `cacheVolume`, `logLevel`                                                                                        | Remaining `dev.containers.*` keys.                                                                                                    |

### Shared defaults

Shared, derived, or non-auto-detectable values: package identifiers, download URLs, version-pinned
paths, state keys, and the setting keys the scripts own. These are public and secret-free, but they
are not meant for day-to-day editing.

| Setting                                                             | Default                                    | Purpose                                                                                                                     |
| ------------------------------------------------------------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `advanced.git.defaultInstallDir`                                    | `%USERPROFILE%\PortableGit`                | Fallback when `user.git.installDir` is empty.                                                                               |
| `advanced.git.portableReleaseApiUrl`                                | git-for-windows latest release API         | Where the PortableGit build is discovered.                                                                                  |
| `advanced.git.portableAssetPattern`                                 | `PortableGit-*64-bit.7z.exe`               | Which release asset to download.                                                                                            |
| `advanced.git.homebrewFormula`                                      | `git`                                      | Formula used on macOS/Linux.                                                                                                |
| `advanced.git.homebrewInstallUrl`                                   | Homebrew `install.sh`                      | Used only when Homebrew is missing on Linux.                                                                                |
| `advanced.git.linuxbrewShellenv`                                    | `/home/linuxbrew/.linuxbrew/bin/brew`      | Path used to load brew into the shell after install.                                                                        |
| `advanced.git.credential.windows.helper`                            | `manager`                                  | Git Credential Manager.                                                                                                     |
| `advanced.git.credential.windows.credentialStore`                   | `wincredman`                               | Windows Credential Manager backing store.                                                                                   |
| `advanced.git.credential.windows.guiPrompt`                         | `false`                                    | Keeps GCM from opening blocking dialogs.                                                                                    |
| `advanced.git.credential.macos.helper`                              | `osxkeychain`                              | Applied when the helper exists.                                                                                             |
| `advanced.git.credential.linux.helper`                              | `manager`                                  | Applied when the helper exists.                                                                                             |
| `advanced.python.wingetPackageId`                                   | `Python.Python.{version}`                  | `{version}` is replaced by `user.python.version`.                                                                           |
| `advanced.python.windowsInstallRoot`                                | `%LOCALAPPDATA%\Programs\Python`           | Where an existing interpreter is discovered.                                                                                |
| `advanced.python.uvInstallUrl.windows`                              | `https://astral.sh/uv/install.ps1`         | uv bootstrap, used only if winget is unavailable.                                                                           |
| `advanced.python.uvInstallUrl.unix`                                 | `https://astral.sh/uv/install.sh`          | uv bootstrap on macOS/Linux.                                                                                                |
| `advanced.python.uvWindowsPath`                                     | `%USERPROFILE%\.local\bin\uv.exe`          | Where the Windows uv bootstrap lands.                                                                                       |
| `advanced.node.wingetPackageId`                                     | `OpenJS.NodeJS.LTS`                        | Also substituted into `windowsSearchPaths`.                                                                                 |
| `advanced.node.homebrewFormula`                                     | `node`                                     | Formula used on macOS/Linux.                                                                                                |
| `advanced.node.windowsSearchPaths`                                  | 3 paths                                    | Where `node.exe` is located after a winget install. `{wingetPackageId}` is substituted.                                     |
| `advanced.vscode.profileDirectories`                                | per-OS stable/insiders paths               | Uses `%VAR%` on Windows and `$HOME` elsewhere.                                                                              |
| `advanced.vscode.managedSettingKeys.gitPath`                        | `git.path`                                 | Setting written with the resolved Git path.                                                                                 |
| `advanced.vscode.managedSettingKeys.pythonInterpreter`              | `python.defaultInterpreterPath`            | Setting written with the resolved interpreter.                                                                              |
| `advanced.vscode.managedSettingKeys.pythonGlobalModuleInstallation` | `python.globalModuleInstallation`          | Setting written from `user.python.allowGlobalPackageInstalls`.                                                              |
| `advanced.vscode.settingsSync.stateDbRelativePath`                  | `globalStorage/state.vscdb`                | VS Code user-data state database used only to detect whether sync is already enabled.                                       |
| `advanced.vscode.settingsSync.enabledKey`                           | `sync.enable`                              | State key that must be `true` before the setup requests sync.                                                               |
| `advanced.vscode.settingsSync.accountProviderKey`                   | `userDataSyncAccountProvider`              | State key checked against `user.vscode.settingsSync.requiredProvider`.                                                      |
| `advanced.vscode.settingsSync.syncCliArgs`                          | `["--sync","on"]`                          | VS Code CLI arguments used to request a sync after validation passes.                                                       |
| `advanced.vscode.extensionCli`                                      | `stable: code`, `insiders: code-insiders`  | CLI used to install extensions per profile. A profile is skipped when its CLI is not on `PATH` or a known install location. |
| `advanced.vscode.extensionCliFallbackPaths`                         | per-OS stable/insiders paths               | Well-known install locations checked on macOS/Linux when the CLI isn't on `PATH`.                                           |
| `advanced.vscode.mcpFileName`                                       | `mcp.json`                                 | File written next to `settings.json` in each profile.                                                                       |
| `advanced.vscode.settings`                                          | `azureFunctions.showProjectWarning: false` | Non-devcontainer settings the setup owns.                                                                                   |
| `advanced.devcontainers.dockerAccessFeatures`                       | map of 3 modes                             | Feature refs selected by `user.devcontainers.dockerAccess`.                                                                 |
| `advanced.devcontainers.settingKeys.features`                       | `dev.containers.defaultFeatures`           | Key holding the feature map.                                                                                                |
| `advanced.devcontainers.settingKeys.extensions`                     | `dev.containers.defaultExtensions`         | Key holding the extension list.                                                                                             |
| `advanced.devcontainers.snippet.file`                               | `jsonc.json`                               | Snippet file written under `snippets/`.                                                                                     |
| `advanced.devcontainers.snippet.name`                               | `Dev container (Ubuntu base)`              | Snippet entry name.                                                                                                         |
| `advanced.devcontainers.snippet.prefix`                             | `devcontainer`                             | Text typed to expand the snippet.                                                                                           |
| Setting                                                             | Default                                    | Purpose                                                                                                                     |
| -----------------------------------------------------------------   | ------------------------------------------ | -----------------------------------------------------------------------------------------------                             |
| `advanced.git.defaultInstallDir`                                    | `%USERPROFILE%\PortableGit`                | Fallback when `user.git.installDir` is empty.                                                                               |
| `advanced.git.portableReleaseApiUrl`                                | git-for-windows latest release API         | Where the PortableGit build is discovered.                                                                                  |
| `advanced.git.portableAssetPattern`                                 | `PortableGit-*64-bit.7z.exe`               | Which release asset to download.                                                                                            |
| `advanced.git.homebrewFormula`                                      | `git`                                      | Formula used on macOS/Linux.                                                                                                |
| `advanced.git.homebrewInstallUrl`                                   | Homebrew `install.sh`                      | Used only when Homebrew is missing on Linux.                                                                                |
| `advanced.git.linuxbrewShellenv`                                    | `/home/linuxbrew/.linuxbrew/bin/brew`      | Path used to load brew into the shell after install.                                                                        |
| `advanced.git.credential.windows.helper`                            | `manager`                                  | Git Credential Manager.                                                                                                     |
| `advanced.git.credential.windows.credentialStore`                   | `wincredman`                               | Windows Credential Manager backing store.                                                                                   |
| `advanced.git.credential.windows.guiPrompt`                         | `false`                                    | Keeps GCM from opening blocking dialogs.                                                                                    |
| `advanced.git.credential.macos.helper`                              | `osxkeychain`                              | Applied when the helper exists.                                                                                             |
| `advanced.git.credential.linux.helper`                              | `manager`                                  | Applied when the helper exists.                                                                                             |
| `advanced.python.wingetPackageId`                                   | `Python.Python.{version}`                  | `{version}` is replaced by `user.python.version`.                                                                           |
| `advanced.python.windowsInstallRoot`                                | `%LOCALAPPDATA%\Programs\Python`           | Where an existing interpreter is discovered.                                                                                |
| `advanced.python.uvInstallUrl.windows`                              | `https://astral.sh/uv/install.ps1`         | uv bootstrap, used only if winget is unavailable.                                                                           |
| `advanced.python.uvInstallUrl.unix`                                 | `https://astral.sh/uv/install.sh`          | uv bootstrap on macOS/Linux.                                                                                                |
| `advanced.python.uvWindowsPath`                                     | `%USERPROFILE%\.local\bin\uv.exe`          | Where the Windows uv bootstrap lands.                                                                                       |
| `advanced.node.wingetPackageId`                                     | `OpenJS.NodeJS.LTS`                        | Also substituted into `windowsSearchPaths`.                                                                                 |
| `advanced.node.homebrewFormula`                                     | `node`                                     | Formula used on macOS/Linux.                                                                                                |
| `advanced.node.windowsSearchPaths`                                  | 3 paths                                    | Where `node.exe` is located after a winget install. `{wingetPackageId}` is substituted.                                     |
| `advanced.php.homebrewFormula`                                      | `php`                                      | Formula used on macOS/Linux for PHP validation.                                                                             |
| `advanced.php.wingetPackageId`                                      | `PHP.PHP`                                  | Package used on Windows for PHP validation.                                                                                 |
| `advanced.powershell.homebrewFormula`                               | `powershell`                               | Formula used on macOS/Linux for the PowerShell extension.                                                                   |
| `advanced.powershell.wingetPackageId`                               | `Microsoft.PowerShell`                     | Package used on Windows for the PowerShell extension.                                                                       |
| `advanced.vscode.profileDirectories`                                | per-OS stable/insiders paths               | Uses `%VAR%` on Windows and `$HOME` elsewhere.                                                                              |
| `advanced.vscode.managedSettingKeys.gitPath`                        | `git.path`                                 | Setting written with the resolved Git path.                                                                                 |
| `advanced.vscode.managedSettingKeys.pythonInterpreter`              | `python.defaultInterpreterPath`            | Setting written with the resolved interpreter.                                                                              |
| `advanced.vscode.managedSettingKeys.phpValidator`                   | `php.validate.executablePath`              | Setting written with the resolved PHP executable.                                                                           |
| `advanced.vscode.managedSettingKeys.powerShellAdditionalExePaths`   | `powershell.powerShellAdditionalExePaths`  | Setting written with the resolved PowerShell executable.                                                                    |
| `advanced.vscode.extensionCli`                                      | `stable: code`, `insiders: code-insiders`  | CLI used to install extensions per profile. A profile is skipped when its CLI is not on `PATH` or a known install location. |
| `advanced.vscode.extensionCliFallbackPaths`                         | per-OS stable/insiders paths               | Well-known install locations checked on macOS/Linux when the CLI isn't on `PATH`.                                           |
| `advanced.vscode.mcpFileName`                                       | `mcp.json`                                 | File written next to `settings.json` in each profile.                                                                       |
| `advanced.vscode.settings`                                          | `azureFunctions.showProjectWarning: false` | Non-devcontainer settings the setup owns.                                                                                   |
| `advanced.devcontainers.dockerAccessFeatures`                       | map of 3 modes                             | Feature refs selected by `user.devcontainers.dockerAccess`.                                                                 |
| `advanced.devcontainers.settingKeys.features`                       | `dev.containers.defaultFeatures`           | Key holding the feature map.                                                                                                |
| `advanced.devcontainers.settingKeys.extensions`                     | `dev.containers.defaultExtensions`         | Key holding the extension list.                                                                                             |
| `advanced.devcontainers.snippet.file`                               | `jsonc.json`                               | Snippet file written under `snippets/`.                                                                                     |
| `advanced.devcontainers.snippet.name`                               | `Dev container (Ubuntu base)`              | Snippet entry name.                                                                                                         |
| `advanced.devcontainers.snippet.prefix`                             | `devcontainer`                             | Text typed to expand the snippet.                                                                                           |

### Precedence

For VS Code settings, later wins:

1. `advanced.vscode.settings`
2. dev container keys, when `user.install.devcontainerDefaults` is `true`
3. managed Python global package install guidance
4. resolved `git.path` / `python.defaultInterpreterPath`
5. `user.vscode.settings`

Command-line parameters override the config for a single run.

### Extensions

`user.vscode.extensions.install` is a lean, broadly useful baseline rather than an exhaustive list:
formatting and linting (`editorconfig`, `prettier`, `eslint`, `ruff`, `markdownlint`), Python
(`python`, `pylance`, `debugpy`), GitHub (`vscode-github-actions`, `vscode-pull-request-github`),
containers and remote (`remote-containers`, `vscode-containers`), plus `powershell`, `yaml`,
`makefile-tools`, `code-spell-checker`, and `markdown-all-in-one`.

Stack-specific extensions are intentionally left out — Azure, Go, Swift, docs-authoring, and similar
belong to individual workflows, not a shared baseline. Add whatever you need to the list.

`user.vscode.extensions.block` covers extensions that are **deprecated or superseded** by something
in the install list, so having both causes duplicate diagnostics or fighting formatters:

| Blocked                                                              | Superseded by                                   |
| -------------------------------------------------------------------- | ----------------------------------------------- |
| `ms-python.autopep8`, `black-formatter`, `flake8`, `isort`, `pylint` | `charliermarsh.ruff`                            |
| `ms-azuretools.vscode-docker`                                        | `ms-azuretools.vscode-containers`               |
| `ms-vscode.vscode-typescript-tslint-plugin`                          | `dbaeumer.vscode-eslint` (TSLint is deprecated) |
| `hookyqr.beautify`                                                   | `esbenp.prettier-vscode` (unmaintained)         |
| `ms-vscode.powershell-preview`                                       | `ms-vscode.powershell`                          |
| `eg2.vscode-npm-script`, `ms-vscode.node-debug2`                     | Built into VS Code                              |

Blocked extensions are reported, not removed, unless `uninstallBlocked` is `true`. An extension
listed in both `install` and `block` is a configuration error and fails the run.

Extension management needs the VS Code CLI (`code`) on `PATH`. Profiles whose CLI is missing are
reported as `[skip]` and everything else still runs.

### MCP servers

`user.mcp.servers` is merged into each profile's `mcp.json`. The shipped default is four servers
that need **no authentication and no local runtime beyond `npx`/`uvx`**:

| Server                               | Transport     | Why it is a default                                       |
| ------------------------------------ | ------------- | --------------------------------------------------------- |
| `io.github.github/github-mcp-server` | http          | Repos, issues, PRs. Useful in any repository.             |
| `microsoftdocs/mcp`                  | http          | Microsoft/Azure documentation lookup. No auth.            |
| `microsoft/markitdown`               | stdio (`uvx`) | Converts PDFs/Office docs to Markdown. Language-agnostic. |
| `microsoft/playwright-mcp`           | stdio (`npx`) | Browser automation for front-end work.                    |

Servers that are **not** shipped as defaults, and why:

| Not included                          | Reason                                                                                                       |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Azure, Azure DevOps, NuGet, Terraform | Require a subscription, an organization name, a token, or a .NET/Terraform stack. Useful, but not universal. |
| Enterprise and Sentinel endpoints     | Tenant-entitled URLs. They fail for anyone without the entitlement.                                          |
| Next.js devtools, awesome-copilot     | Framework-specific, or require a local Docker daemon.                                                        |

Add any of these to `user.mcp.servers` yourself — the merge handles them the same way.

**Existing entries are never overwritten.** Only missing servers are added, so a locally pinned
version or an added `env` block survives a re-run. Remove a server from `mcp.json` and it comes back
on the next run; add it to `user.mcp.block` to stop that.

**Never hardcode secrets.** Use VS Code's `${input:id}` placeholders with matching entries in
`user.mcp.inputs` and mark secret prompts with `"password": true`. VS Code prompts for those values
locally instead of storing them in this repository.

A server that references an `${input:id}` with no matching definition fails the run, as does a
server listed in both `servers` and `block`.

### Settings deliberately excluded

`user.vscode.settings` holds portable editor, Git, terminal, and security preferences. Some
categories are **intentionally not** shipped here:

| Excluded                                                                                                              | Why                                                                                                                                                                           |
| --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `git.path`, `python.defaultInterpreterPath`                                                                           | Machine-local; resolved and written by the installers.                                                                                                                        |
| `azureResourceGroups.selectedSubscriptions`, `@azure.argTenant`, `chat.mcp.serverSampling`                            | Contain tenant/subscription identifiers. Never commit these to a shared repo.                                                                                                 |
| `yaml.schemas`                                                                                                        | Absolute paths containing a username. Already in `settingsSync.ignoredSettings`.                                                                                              |
| `terminal.integrated.cwd`                                                                                             | A personal folder convention.                                                                                                                                                 |
| `chat.tools.global.autoApprove`, `chat.agent.sandbox.*`, `chat.agent.networkFilter`, `chat.tools.*.autoApprove`       | Agent security posture. Auto-approving tool calls and disabling the sandbox is a personal risk decision and must not be a shared default. Set them yourself if you want them. |
| Other `chat.*` / `github.copilot.*` tuning                                                                            | Fast-moving setting names and highly personal. Add to `user.vscode.settings` if you want them synced.                                                                         |
| Excluded                                                                                                              | Why                                                                                                                                                                           |
| --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `git.path`, `python.defaultInterpreterPath`, `php.validate.executablePath`, `powershell.powerShellAdditionalExePaths` | Machine-local; resolved and written by the installers. The PHP and PowerShell path settings are ignored by Settings Sync.                                                     |
| `azureResourceGroups.selectedSubscriptions`, `@azure.argTenant`, `chat.mcp.serverSampling`                            | Contain tenant/subscription identifiers. Never commit these to a shared repo.                                                                                                 |
| `yaml.schemas`                                                                                                        | Absolute paths containing a username. Already in `settingsSync.ignoredSettings`.                                                                                              |
| `terminal.integrated.cwd`                                                                                             | A personal folder convention.                                                                                                                                                 |
| `chat.tools.global.autoApprove`, `chat.agent.sandbox.*`, `chat.agent.networkFilter`, `chat.tools.*.autoApprove`       | Agent security posture. Auto-approving tool calls and disabling the sandbox is a personal risk decision and must not be a shared default. Set them yourself if you want them. |
| Other `chat.*` / `github.copilot.*` tuning                                                                            | Fast-moving setting names and highly personal. Add to `user.vscode.settings` if you want them synced.                                                                         |

Anything in this list can still be added to `user.vscode.settings` on your own machine — the config
is yours to extend.

### Path placeholders

Config values may contain environment placeholders, expanded at read time:

| Form                | Platform      | Example                                      |
| ------------------- | ------------- | -------------------------------------------- |
| `%VAR%`             | Windows       | `%APPDATA%\Code\User`                        |
| `$HOME`             | macOS / Linux | `$HOME/.config/Code/User`                    |
| `{version}`         | any           | `Python.Python.{version}`                    |
| `{wingetPackageId}` | any           | `...\WinGet\Packages\{wingetPackageId}*\...` |

## Shared code reference

### `src/config.ps1` (dot-source it)

| Name                                                  | Kind     | Purpose                                                           |
| ----------------------------------------------------- | -------- | ----------------------------------------------------------------- |
| `$DevSetupRoot`                                       | variable | Repository root, resolved from the file's own location.           |
| `$DevSetupConfigPath`                                 | variable | Default config path under `config/`.                              |
| `Get-DevSetupConfig [-Path]`                          | function | Load and parse the config; warns and returns empty if absent.     |
| `Get-DevSetupValue $cfg <dotted.key> [$default]`      | function | Safe lookup. `null` and `""` fall back to `$default`.             |
| `Expand-DevSetupPath <value>`                         | function | Expand `%VAR%` placeholders.                                      |
| `ConvertTo-DevSetupHashtable <object>`                | function | `PSCustomObject` to hashtable for iteration.                      |
| `Write-DevSetupStatus <state> <component> [detail]`   | function | Emit one `[found]/[install]/[skip]/[warn]` line.                  |
| `Get-DevSetupVSCodeProfilePath $cfg [-Platform]`      | function | Existing `settings.json` paths for configured profiles.           |
| `Set-DevSetupVSCodeSetting $cfg <key> <value>`        | function | Write one setting to every profile, skipping no-ops.              |
| `Add-DevSetupUserPath <dir> [-Prepend]`               | function | Add a directory to the user `PATH` once, comparing whole entries. |
| `Get-DevSetupGitCredentialSetting $cfg`               | function | The git config keys/values this setup owns on Windows.            |
| `Write-DevSetupGitIdentityStatus $cfg <git> [-Audit]` | function | Identity reporting shared by audit and apply.                     |

```powershell
. (Join-Path $PSScriptRoot "..\config.ps1")
$config = Get-DevSetupConfig
$version = Get-DevSetupValue $config "user.python.version" "3.14"
```

### `src/config.sh` (source it)

| Name                                           | Kind     | Purpose                                                                      |
| ---------------------------------------------- | -------- | ---------------------------------------------------------------------------- |
| `DEVSETUP_ROOT`                                | variable | Repository root, resolved from the file's own location.                      |
| `DEVSETUP_CONFIG_FILE`                         | variable | Config path. Override by exporting it before sourcing.                       |
| `DEVSETUP_READER`                              | variable | The JSON reader (`python3`, `python`, or `jq`) resolved once at source time. |
| `devsetup_config <dotted.key> [default]`       | function | Safe lookup. Arrays print newline-separated.                                 |
| `devsetup_enabled <dotted.key> [default]`      | function | True when the value is `true`.                                               |
| `devsetup_status <state> <component> [detail]` | function | Emit one status line.                                                        |
| `devsetup_git_identity_status [audit]`         | function | Identity reporting shared by audit and apply.                                |
| `devsetup_config_reader`                       | function | Prints `DEVSETUP_READER`; fails if none was found.                           |

```bash
. "$(dirname "$0")/../config.sh"
version="$(devsetup_config user.python.version 3.14)"
```

The config must be readable _before_ Python is installed, so the reader is chosen from `python3`,
`python`, then `jq`, and every lookup falls back to the caller-supplied default if none exist.
Resolution happens at source time rather than per lookup: `devsetup_config` runs inside a `$( )`
subshell, so a value cached during a lookup would be discarded.

## Individual scripts

Each installer runs standalone and accepts `-Audit` / `--audit`.

### Git

```powershell
.\src\scripts\install-portable-git.ps1 [-ConfigureVSCode] [-ForcePortable] [-Audit]
```

```bash
./src/scripts/install-portable-git.sh [--audit]
```

- **Windows** downloads the latest [Git for Windows portable build](https://github.com/git-for-windows/git/releases)
  to the configured directory and adds it to the user `PATH`. An existing Git on `PATH` is detected
  and the download skipped unless `user.git.forcePortable` is `true`.
- **macOS** reports and exits if Git and Xcode Command Line Tools are both missing; Apple offers no
  silent install path, so run `xcode-select --install` once yourself.
- **Linux** uses an existing Git or Homebrew, otherwise installs
  [Homebrew for Linux](https://docs.brew.sh/Homebrew-on-Linux) under `$HOME` (no root) and installs
  Git through it.
- Configures the credential helper and applies `user.git.userName` / `user.git.userEmail` when set.
  Each value is compared first, so a second run reports `[found]`.
- `-ConfigureVSCode` points `git.path` at the resolved binary across every configured profile.

### Python

```powershell
.\src\scripts\install-python.ps1 [-ConfigureVSCode] [-PythonVersion <x.y>] [-Audit]
```

```bash
./src/scripts/install-python.sh [--print-path] [--audit]
```

Checks for a working interpreter first. On Windows it installs per-user via `winget` when
available — winget packages go through a trusted pipeline and are not blocked by Defender
Application Control / Exploit Guard ASR policies common on managed corporate devices, whereas
executing a freshly downloaded `uv.exe` can be. If `winget` is unavailable, both platforms fall back
to `uv` in a user-local location.

The version comes from `user.python.version` on every platform. The PowerShell script emits the
resolved interpreter path as its final pipeline value; the shell script does the same under
`--print-path`, with progress on stderr.

### Node.js and npm

```powershell
.\src\scripts\install-node.ps1 [-Audit]
```

```bash
./src/scripts/install-node.sh [--audit]
```

Windows installs Node.js LTS per-user through `winget`; macOS/Linux use Homebrew. If PowerShell
execution policy blocks `npm.ps1`, use `npm.cmd install` / `npm.cmd test` — the same executable,
without changing machine security policy.

### PHP

```bash
./src/scripts/install-php.sh [--print-path] [--audit]
```

macOS/Linux use Homebrew and Windows uses WinGet to install PHP when it is missing. The resolved executable is written
to VS Code's `php.validate.executablePath`, which restores built-in PHP validation. That absolute
path is machine-local and explicitly excluded from Settings Sync.

### PowerShell

```powershell
.\src\scripts\install-powershell.ps1 [-Audit]
```

```bash
./src/scripts/install-powershell.sh [--print-path] [--audit]
```

macOS/Linux use Homebrew and Windows uses WinGet to install PowerShell 7 when it is missing. The
resolved `pwsh` path is written to `powershell.powerShellAdditionalExePaths`, restoring discovery
for the VS Code PowerShell extension. The path is machine-local and excluded from Settings Sync.

### VS Code settings

```powershell
python .\src\configure-vscode.py [--dry-run] [--config <path>] [--git-path <p>] [--python-path <p>] [--php-path <p>] [--powershell-path <p>]
```

```bash
python3 ./src/configure-vscode.py [--dry-run]
```

One cross-platform script, so the settings payload has a single definition. It writes two files per
configured profile, both covered by Settings Sync:

- `settings.json` — the merged settings described in [Precedence](#precedence).
- `snippets/jsonc.json` — a `devcontainer` snippet. Type `devcontainer` in a new
  `.devcontainer/devcontainer.json`.
- `mcp.json` — the configured MCP servers.

It then reconciles extensions through the VS Code CLI: installs anything missing from
`user.vscode.extensions.install`, and reports (or removes) anything present from `.block`. See
[Extensions](#extensions).

Finally it merges `user.mcp.servers` into each profile's `mcp.json`. See [MCP servers](#mcp-servers).
After writes finish, it validates the managed settings, snippet, extension list, and MCP entries by
rereading the files and VS Code CLI output. If validation passes, `user.vscode.settingsSync` allows
one final guarded sync request: the script checks VS Code's global user-data state for
`sync.enable=true` and the configured account provider, then runs the configured VS Code CLI sync
arguments. It skips sync when Settings Sync is off, the provider is not GitHub, or the CLI is absent.

The merge is additive and idempotent: existing settings and snippets are preserved, and JSONC
comments and trailing commas are tolerated on read. The file is rewritten as plain JSON, so comments
in `settings.json` are **not** preserved.

Settings Sync itself must still be enabled once from VS Code's Accounts menu — OAuth cannot be scripted.
Binaries, `PATH` entries, credentials, and git identity stay machine-local and are never uploaded.

## Repository hygiene

The repository is public and keeps only portable defaults in source control.

| Area                     | Current posture                                                                                 |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| Community defaults       | Funding, issue templates, and PR templates are inherited from the org-level `.github` repo.     |
| Org automation config    | `.github/bos-universal-config.json` opts into common sync/lint settings only.                   |
| CODEOWNERS               | `.github/CODEOWNERS` requests security review for every PR.                                     |
| Issues                   | Enabled for support and bug reports.                                                            |
| Projects and Discussions | Disabled; this kit is small enough to keep planning in issues and PRs.                          |
| Wiki                     | Disabled; public docs live in `README.md`, `SECURITY.md`, and `CONTRIBUTING.md`.                |
| Branch cleanup           | Delete branch on merge is enabled in GitHub repository settings.                                |
| Secrets                  | No credentials, tokens, tenant IDs, subscription IDs, or private endpoints belong in this repo. |
| Workflows                | No action/release workflow is copied because this repo has no `action.yml` or package manifest. |

## Dev container defaults

Dev containers stay **opt-in**. Nothing here creates a `.devcontainer` folder or puts a workspace
into a container; VS Code only containerizes a repo that already has a `.devcontainer/devcontainer.json`.
These are the defaults applied _if_ a container is built.

The default `user.devcontainers.dockerAccess` is `outside-of-docker`, which bind-mounts the host
Docker socket. The container shares the host image cache (no double-pull) and needs no `--privileged`
flag. Two consequences:

- Paths in nested `docker run -v` calls resolve against the **host** filesystem, not the container's.
  Use `${localWorkspaceFolder}` rather than `$(pwd)`. This is the usual cause of confusing failures
  with `act` and nested Compose.
- Socket access is root-equivalent on the host. Fine on a personal machine; not appropriate on
  shared or untrusted infrastructure.

Set `dockerAccess` to `in-docker` for true daemon isolation, accepting `--privileged` and a cold
image cache, or `none` to add no Docker feature at all.

## Troubleshooting

### Set your git identity

Fill `user.git.userName` and `user.git.userEmail` in the config and the setup applies them.
Use a GitHub noreply address if you do not want to expose a personal email address.

### `PATH` changes are not visible

The scripts update the **user-level** `PATH`, which existing shells do not inherit. Open a new
terminal, or reload VS Code.

### Docker Desktop re-prompts for file sharing on non-`C:` drives

If Docker Desktop shows a **Filesharing** dialog every time you run `docker compose`/`docker run`
for a project on a drive other than `C:`, this is Docker Desktop/Windows behavior, not something
VS Code or Settings Sync controls:

- With the **Hyper-V backend**, Settings → Resources → **File sharing** pre-authorizes a directory
  once.
- With the **WSL 2 backend** (the default), that persistent allow-list does not exist for drives WSL
  does not auto-mount, so Docker re-prompts per session by design. Updating Docker Desktop does not
  fix it.

Options: keep the project on `C:`, work inside the WSL distro's own filesystem and run Compose from
within WSL, switch to the Hyper-V backend, or click **Yes** each session.

### PowerShell blocks `npm.ps1`

Use `npm.cmd` instead of `npm`. Same executable, no security policy change.

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
