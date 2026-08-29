#!/usr/bin/env python3
"""Apply dev-setup's VS Code settings from config/dev-setup.config.json.

Cross-platform so Windows, macOS, and Linux share one implementation and one
settings payload. Writes to VS Code's syncable user profile, so with Settings
Sync enabled the result follows the signed-in GitHub account to other machines.

Dev containers stay opt-in: nothing here creates a .devcontainer folder or puts
a workspace into a container. The dev container keys are the defaults VS Code
applies *if* a container is built.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = REPO_ROOT / "config" / "dev-setup.config.json"

OS_KEYS = {"Windows": "windows", "Darwin": "macos"}


def status(state: str, component: str, detail: str = "") -> None:
    """Match the audit line format used by config.ps1 and config.sh."""
    print(f"  {'[' + state + ']':<9} {component:<8} {detail}")


def get(config: dict, key: str, default: Any = None) -> Any:
    """Look up a dotted path, falling back when absent, null, or blank."""
    node: Any = config
    for segment in key.split("."):
        if not isinstance(node, dict) or segment not in node:
            return default
        node = node[segment]
    if node is None or node == "":
        return default
    return node


def strip_jsonc(text: str) -> str:
    """Drop // and /* */ comments and trailing commas, ignoring string literals."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    break
                j += 1
            out.append(text[i : j + 1])
            i = j + 1
        elif text.startswith("//", i):
            i = text.find("\n", i)
            if i == -1:
                break
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
        else:
            out.append(ch)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    raw = path.read_text(encoding="utf-8-sig")
    if not raw.strip():
        return {}
    try:
        return json.loads(strip_jsonc(raw))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path} is not valid JSON/JSONC: {exc}") from exc


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=4) + "\n", encoding="utf-8")


def profile_dirs(config: dict) -> list[Path]:
    """Resolve the configured VS Code profiles for this OS."""
    os_key = OS_KEYS.get(platform.system(), "linux")
    configured = get(config, f"advanced.vscode.profileDirectories.{os_key}", {})
    wanted = get(config, "user.vscode.profiles", ["stable", "insiders"])
    return [
        Path(os.path.expandvars(configured[name]))
        for name in wanted
        if name in configured
    ]


def build_settings(config: dict, git_path: str | None, python_path: str | None) -> dict:
    settings: dict[str, Any] = {}
    settings.update(get(config, "advanced.vscode.settings", {}))

    if get(config, "user.install.devcontainerDefaults", True):
        features = dict(get(config, "user.devcontainers.features", {}))
        access = get(config, "user.devcontainers.dockerAccess", "outside-of-docker")
        docker = get(config, f"advanced.devcontainers.dockerAccessFeatures.{access}")
        if docker is None:
            raise SystemExit(
                f"user.devcontainers.dockerAccess '{access}' has no matching entry "
                "in advanced.devcontainers.dockerAccessFeatures."
            )
        features.update(docker)

        feature_key = get(
            config,
            "advanced.devcontainers.settingKeys.features",
            "dev.containers.defaultFeatures",
        )
        extension_key = get(
            config,
            "advanced.devcontainers.settingKeys.extensions",
            "dev.containers.defaultExtensions",
        )
        settings[feature_key] = features
        settings[extension_key] = get(config, "user.devcontainers.extensions", [])
        settings.update(get(config, "user.devcontainers.settings", {}))

    # Machine-local paths: never written unless the caller resolved them.
    if git_path:
        settings[get(config, "advanced.vscode.managedSettingKeys.gitPath", "git.path")] = git_path
    if python_path:
        settings[
            get(
                config,
                "advanced.vscode.managedSettingKeys.pythonInterpreter",
                "python.defaultInterpreterPath",
            )
        ] = python_path

    # User overrides win over everything above.
    settings.update(get(config, "user.vscode.settings", {}))
    return settings


def build_snippet(config: dict) -> tuple[str, str, dict] | None:
    if not get(config, "user.install.devcontainerDefaults", True):
        return None
    snippet_file = get(config, "advanced.devcontainers.snippet.file", "jsonc.json")
    name = get(config, "advanced.devcontainers.snippet.name", "Dev container")
    prefix = get(config, "advanced.devcontainers.snippet.prefix", "devcontainer")
    image = get(
        config,
        "user.devcontainers.baseImage",
        "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
    )
    remote_user = get(config, "user.devcontainers.remoteUser", "vscode")
    body = {
        "prefix": prefix,
        "description": (
            "Minimal dev container. Shared tooling comes from "
            "dev.containers.defaultFeatures / defaultExtensions in user settings."
        ),
        "body": [
            "{",
            '  "name": "${1:dev}",',
            f'  "image": "{image}",',
            '  "features": {',
            "    ${2}",
            "  },",
            f'  "remoteUser": "{remote_user}",',
            '  "postCreateCommand": "${3:echo ready}"',
            "}",
        ],
    }
    return snippet_file, name, body


def apply(user_dir: Path, settings: dict, snippet, dry_run: bool) -> bool:
    verb = "would set" if dry_run else "set"
    changes: list[str] = []

    settings_path = user_dir / "settings.json"
    current = load_json(settings_path)
    for key, value in settings.items():
        if current.get(key) != value:
            current[key] = value
            changes.append(key)

    snippets_path = None
    snippets: dict = {}
    if snippet:
        snippet_file, name, body = snippet
        snippets_path = user_dir / "snippets" / snippet_file
        snippets = load_json(snippets_path)
        if snippets.get(name) != body:
            snippets[name] = body
            changes.append(f"snippet {name!r}")

    if not changes:
        status("found", "vscode", f"already up to date ({user_dir})")
        return False

    status("install", "vscode", f"{verb} {len(changes)} setting(s) in {user_dir}")
    for name in changes:
        print(f"             - {name}")

    if not dry_run:
        write_json(settings_path, current)
        if snippets_path is not None:
            write_json(snippets_path, snippets)
    return True


def assert_no_overlap(wanted, blocked, kind: str, setting: str) -> None:
    """Listing something as both wanted and blocked is ambiguous, so fail loudly."""
    overlap = sorted(set(wanted) & set(blocked))
    if overlap:
        raise SystemExit(
            f"These {kind} are in both {setting} and .block: {', '.join(overlap)}"
        )


def run_cli(cli: str, *args: str) -> tuple[int, str]:
    result = subprocess.run(
        [cli, *args], capture_output=True, text=True, check=False
    )
    return result.returncode, (result.stdout or "") + (result.stderr or "")


def manage_extensions(config: dict, dry_run: bool) -> None:
    """Install the recommended extensions and report or remove blocked ones."""
    if not get(config, "user.vscode.extensions.manage", True):
        status("skip", "ext", "user.vscode.extensions.manage is false")
        return

    wanted = [e.lower() for e in get(config, "user.vscode.extensions.install", [])]
    blocked = [e.lower() for e in get(config, "user.vscode.extensions.block", [])]
    uninstall_blocked = get(config, "user.vscode.extensions.uninstallBlocked", False)

    assert_no_overlap(wanted, blocked, "extensions", "user.vscode.extensions.install")
    if not wanted and not blocked:
        return

    clis = get(config, "advanced.vscode.extensionCli", {})
    for profile in get(config, "user.vscode.profiles", ["stable", "insiders"]):
        command = clis.get(profile)
        if not command:
            continue
        cli = shutil.which(command)
        if not cli:
            status("skip", "ext", f"'{command}' CLI not on PATH ({profile})")
            continue

        code, output = run_cli(cli, "--list-extensions")
        if code != 0:
            status("warn", "ext", f"{command} --list-extensions failed ({profile})")
            continue
        installed = {line.strip().lower() for line in output.splitlines() if line.strip()}

        missing = [e for e in wanted if e not in installed]
        present_blocked = [e for e in blocked if e in installed]

        if not missing:
            status("found", "ext", f"all {len(wanted)} recommended present ({profile})")
        for ext in missing:
            if dry_run:
                status("install", "ext", f"would install {ext} ({profile})")
                continue
            code, output = run_cli(cli, "--install-extension", ext, "--force")
            if code == 0:
                status("install", "ext", f"installed {ext} ({profile})")
            else:
                status("warn", "ext", f"failed to install {ext}: {output.strip()[:120]}")

        for ext in present_blocked:
            if not uninstall_blocked:
                status("warn", "ext", f"{ext} is blocked but installed ({profile})")
                continue
            if dry_run:
                status("install", "ext", f"would uninstall blocked {ext} ({profile})")
                continue
            code, output = run_cli(cli, "--uninstall-extension", ext)
            if code == 0:
                status("install", "ext", f"uninstalled blocked {ext} ({profile})")
            else:
                status("warn", "ext", f"failed to uninstall {ext}: {output.strip()[:120]}")


def manage_mcp(config: dict, dry_run: bool) -> None:
    """Merge the configured MCP servers into each profile's mcp.json.

    Servers already present are left alone rather than overwritten, so a locally
    pinned version or an added env block survives a re-run.
    """
    if not get(config, "user.install.mcpServers", True) or not get(
        config, "user.mcp.manage", True
    ):
        status("skip", "mcp", "MCP management is disabled in config")
        return

    servers = get(config, "user.mcp.servers", {})
    inputs = get(config, "user.mcp.inputs", [])
    blocked = get(config, "user.mcp.block", [])
    remove_blocked = get(config, "user.mcp.removeBlocked", False)

    assert_no_overlap(servers, blocked, "MCP servers", "user.mcp.servers")
    if not servers and not blocked:
        return

    # An ${input:id} with no matching entry leaves VS Code prompting for nothing.
    referenced = set(re.findall(r"\$\{input:([A-Za-z0-9_-]+)\}", json.dumps(servers)))
    defined = {i.get("id") for i in inputs}
    if referenced - defined:
        raise SystemExit(
            "user.mcp.servers reference inputs that are not defined in "
            f"user.mcp.inputs: {', '.join(sorted(referenced - defined))}"
        )

    filename = get(config, "advanced.vscode.mcpFileName", "mcp.json")
    verb = "would add" if dry_run else "added"

    for user_dir in profile_dirs(config):
        if not user_dir.is_dir():
            continue
        path = user_dir / filename
        current = load_json(path)
        existing = current.get("servers") or {}

        added = [name for name in servers if name not in existing]
        present_blocked = [name for name in blocked if name in existing]

        changed = False
        for name in added:
            existing[name] = servers[name]
            changed = True
        for name in present_blocked:
            if remove_blocked:
                del existing[name]
                changed = True
            else:
                status("warn", "mcp", f"{name} is blocked but configured")

        current_inputs = current.get("inputs") or []
        known = {i.get("id") for i in current_inputs}
        new_inputs = [i for i in inputs if i.get("id") not in known]
        if new_inputs:
            current_inputs.extend(new_inputs)
            changed = True

        if not changed:
            status("found", "mcp", f"all {len(servers)} server(s) already configured")
            continue

        if added:
            status("install", "mcp", f"{verb} {len(added)} server(s): {', '.join(added)}")
        if remove_blocked and present_blocked:
            status("install", "mcp", f"removed blocked: {', '.join(present_blocked)}")
        if new_inputs:
            status("install", "mcp", f"{verb} {len(new_inputs)} input definition(s)")

        if not dry_run:
            current["servers"] = existing
            if current_inputs:
                current["inputs"] = current_inputs
            write_json(path, current)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--git-path", help="value for the managed git.path setting")
    parser.add_argument("--python-path", help="value for the managed interpreter setting")
    parser.add_argument(
        "--dry-run", action="store_true", help="report changes without writing files"
    )
    args = parser.parse_args()

    config = load_json(args.config)
    if not config:
        print(f"Config not found at {args.config}; using built-in defaults.")

    if not get(config, "user.install.vscodeSettings", True):
        status("skip", "vscode", "user.install.vscodeSettings is false")
        return 0

    settings = build_settings(config, args.git_path, args.python_path)
    snippet = build_snippet(config)

    targets = [d for d in profile_dirs(config) if d.is_dir()]
    if not targets:
        status("skip", "vscode", "no VS Code user profile found on this machine")
    else:
        for user_dir in targets:
            apply(user_dir, settings, snippet, args.dry_run)

    manage_extensions(config, args.dry_run)
    manage_mcp(config, args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
