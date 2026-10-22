import importlib.util
import json
import os
import sys
import tempfile
import unittest
import subprocess
import sqlite3
from pathlib import Path
from contextlib import closing
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "src" / "configure-vscode.py"
SPEC = importlib.util.spec_from_file_location("configure_vscode", SOURCE)
assert SPEC is not None and SPEC.loader is not None
configure_vscode = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = configure_vscode
SPEC.loader.exec_module(configure_vscode)


class CopilotMcpConfigTests(unittest.TestCase):
    def test_uses_copilot_home_when_configured(self):
        with patch.dict(os.environ, {"COPILOT_HOME": "~/copilot-home"}):
            self.assertEqual(
                configure_vscode.copilot_mcp_config_path(),
                Path.home() / "copilot-home" / "mcp-config.json",
            )

    def test_converts_portable_server_and_defaults_tool_allowlist(self):
        server = {
            "type": "http",
            "url": "https://example.test/mcp",
        }

        self.assertEqual(
            configure_vscode.copilot_mcp_server(server),
            {
                "type": "http",
                "url": "https://example.test/mcp",
                "tools": ["*"],
            },
        )

    def test_skips_vscode_inputs_and_unsupported_metadata(self):
        self.assertIsNone(
            configure_vscode.copilot_mcp_server(
                {
                    "type": "http",
                    "url": "${input:server-url}",
                }
            )
        )
        self.assertIsNone(
            configure_vscode.copilot_mcp_server(
                {
                    "type": "stdio",
                    "command": "uvx",
                    "gallery": "https://registry.example.test",
                }
            )
        )
        self.assertIsNone(
            configure_vscode.copilot_mcp_server(
                {
                    "type": "sse",
                    "url": "https://example.test/sse",
                }
            )
        )

    def test_dry_run_is_read_only_and_apply_is_additive(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            config_path = Path(temp_dir) / "mcp-config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "mcpServers": {
                            "existing": {
                                "type": "http",
                                "url": "https://local.example.test/mcp",
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            config = {
                "user": {
                    "mcp": {
                        "servers": {
                            "existing": {
                                "type": "http",
                                "url": "https://managed.example.test/mcp",
                            },
                            "new": {
                                "type": "stdio",
                                "command": "uvx",
                                "args": ["example-server"],
                            },
                            "interactive": {
                                "type": "http",
                                "url": "${input:server-url}",
                            },
                        }
                    }
                }
            }

            with patch(
                "configure_vscode.copilot_mcp_config_path",
                return_value=config_path,
            ):
                configure_vscode.manage_copilot_mcp(config, dry_run=True)
                self.assertNotIn(
                    "new",
                    json.loads(config_path.read_text(encoding="utf-8"))["mcpServers"],
                )

                configure_vscode.manage_copilot_mcp(config, dry_run=False)
                saved = json.loads(config_path.read_text(encoding="utf-8"))
                self.assertEqual(
                    saved["mcpServers"]["existing"]["url"],
                    "https://local.example.test/mcp",
                )
                self.assertEqual(
                    saved["mcpServers"]["new"]["tools"],
                    ["*"],
                )
                self.assertNotIn("interactive", saved["mcpServers"])

                configure_vscode.manage_copilot_mcp(config, dry_run=False)
                self.assertEqual(
                    json.loads(config_path.read_text(encoding="utf-8")),
                    saved,
                )

    def test_rejects_non_object_mcp_servers(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "mcp-config.json"
            path.write_text('{"mcpServers": []}', encoding="utf-8")
            with self.assertRaises(SystemExit):
                configure_vscode.current_copilot_mcp_servers(
                    json.loads(path.read_text(encoding="utf-8")),
                    path,
                )


class GitHubMcpSetupTests(unittest.TestCase):
    def setUp(self):
        self.config = configure_vscode.load_json(configure_vscode.DEFAULT_CONFIG)
        self.server_name = "io.github.github/github-mcp-server"
        self.server = self.config["user"]["mcp"]["servers"][self.server_name]

    def test_official_remote_and_github_sync_are_shipped_defaults(self):
        self.assertEqual(
            self.server,
            {"type": "http", "url": "https://api.githubcopilot.com/mcp/"},
        )
        self.assertTrue(self.config["user"]["install"]["mcpServers"])
        self.assertTrue(self.config["user"]["mcp"]["manage"])
        self.assertTrue(self.config["user"]["mcp"]["copilotConfig"]["manage"])
        sync = self.config["user"]["vscode"]["settingsSync"]
        self.assertTrue(sync["syncAfterSetup"])
        self.assertEqual(sync["requiredProvider"], "github")
        self.assertEqual(
            configure_vscode.copilot_mcp_servers(self.config)[self.server_name],
            {**self.server, "tools": ["*"]},
        )

    def test_audit_apply_and_second_run_preserve_profile_and_copilot_config(self):
        self.config["user"]["mcp"]["servers"] = {self.server_name: self.server}
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            profiles = [(name, root / name) for name in ("stable", "insiders")]
            existing_server = {"type": "http", "url": "https://example.test/mcp"}
            profile_original = {
                "servers": {"existing": existing_server},
                "inputs": [{"id": "existing", "type": "promptString"}],
            }
            for _, user_dir in profiles:
                configure_vscode.write_json(user_dir / "mcp.json", profile_original)
            copilot_path = root / "copilot" / "mcp-config.json"
            copilot_original = {"mcpServers": {"existing": existing_server}}
            configure_vscode.write_json(copilot_path, copilot_original)
            paths = [user_dir / "mcp.json" for _, user_dir in profiles] + [copilot_path]

            def snapshots():
                return {
                    path: (path.read_bytes(), path.stat().st_mtime_ns)
                    for path in paths
                }

            with (
                patch("configure_vscode.profile_targets", return_value=profiles),
                patch("configure_vscode.copilot_mcp_config_path", return_value=copilot_path),
            ):
                before = snapshots()
                configure_vscode.manage_mcp(self.config, dry_run=True)
                configure_vscode.manage_copilot_mcp(self.config, dry_run=True)
                self.assertEqual(snapshots(), before)

                configure_vscode.manage_mcp(self.config, dry_run=False)
                configure_vscode.manage_copilot_mcp(self.config, dry_run=False)
                configure_vscode.validate_mcp(self.config)
                configure_vscode.validate_copilot_mcp(self.config)
                for _, user_dir in profiles:
                    self.assertEqual(
                        configure_vscode.load_json(user_dir / "mcp.json"),
                        {
                            **profile_original,
                            "servers": {
                                **profile_original["servers"],
                                self.server_name: self.server,
                            },
                        },
                    )
                self.assertEqual(
                    configure_vscode.load_json(copilot_path),
                    {
                        "mcpServers": {
                            **copilot_original["mcpServers"],
                            self.server_name: {**self.server, "tools": ["*"]},
                        }
                    },
                )

                after = snapshots()
                configure_vscode.manage_mcp(self.config, dry_run=False)
                configure_vscode.manage_copilot_mcp(self.config, dry_run=False)
                self.assertEqual(snapshots(), after)


class DefaultSettingsTests(unittest.TestCase):
    def setUp(self):
        self.config = configure_vscode.load_json(configure_vscode.DEFAULT_CONFIG)

    def settings(self):
        return configure_vscode.build_settings(self.config, None, None, None, None)

    def test_playwright_extension_is_in_the_managed_profile_baseline(self):
        extensions = self.config["user"]["vscode"]["extensions"]["install"]
        self.assertIn("ms-playwright.playwright", extensions)

    def test_baseline_keeps_terminals_visible_and_voice_disabled(self):
        settings = self.settings()
        self.assertEqual(settings["chat.requestQueuing.defaultAction"], "queue")
        self.assertEqual(settings["chat.tools.terminal.outputLocation"], "terminal")
        self.assertTrue(settings["chat.tools.terminal.enforceTimeoutFromModel"])
        self.assertEqual(settings["chat.tools.terminal.idleSilenceTimeoutMs"], 60000)
        self.assertFalse(settings["terminal.integrated.enablePersistentSessions"])
        self.assertEqual(settings["terminal.integrated.persistentSessionReviveProcess"], "never")
        self.assertFalse(settings["dictation.enabled"])
        self.assertFalse(settings["agents.voice.enabled"])
        self.assertEqual(settings["window.confirmBeforeClose"], "always")

    def test_unattended_permissions_and_fusion_are_opt_in(self):
        self.assertNotIn("chat.defaultConfiguration", self.settings())
        self.assertNotIn("chat.copilot.ensemble.enabled", self.settings())
        self.config["user"]["vscode"]["copilot"] = {"autopilot": True, "fusion": True}
        settings = self.settings()
        self.assertEqual(
            settings["chat.defaultConfiguration"],
            {"mode": "autopilot", "approvals": "allowAll"},
        )
        self.assertEqual(settings["chat.permissions.default"], "autopilot")
        self.assertTrue(settings["chat.copilot.ensemble.enabled"])
        self.assertEqual(settings["chat.copilot.hydraFusion.enabled"], "v2")
        self.assertEqual(settings["github.copilot.chat.autoModeTierOverride"], "balance")
        self.assertEqual(settings["chat.defaultModel"], "auto")

    def test_user_settings_override_opt_in_presets(self):
        self.config["user"]["vscode"]["copilot"]["autopilot"] = True
        self.config["user"]["vscode"]["settings"]["chat.permissions.default"] = "default"
        self.assertEqual(self.settings()["chat.permissions.default"], "default")

    def test_non_root_devcontainer_and_no_global_python_installs(self):
        self.assertEqual(self.config["user"]["devcontainers"]["remoteUser"], "vscode")
        self.assertFalse(self.settings()["python.globalModuleInstallation"])

    def test_cloud_session_sync_and_its_index_dependency_are_enabled(self):
        settings = self.settings()
        self.assertTrue(settings["chat.sessionSync.enabled"])
        self.assertTrue(settings["github.copilot.chat.localIndex.enabled"])
        self.assertTrue(self.config["user"]["vscode"]["settingsSync"]["syncAfterSetup"])
        self.config["user"]["vscode"]["settings"]["chat.sessionSync.enabled"] = False
        self.assertFalse(self.settings()["chat.sessionSync.enabled"])


class SettingsSyncTests(unittest.TestCase):
    def setUp(self):
        self.real_reader = configure_vscode.read_state_value
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.user_dir = Path(self.temp.name)
        self.config = {
            "advanced": {"vscode": {"extensionCli": {"test": "code"}}},
        }
        self.state = {
            "sync.enable": "true",
            "userDataSyncAccountProvider": "github",
            "userDataSyncAccountPreference": "opaque-account-reference",
        }
        for name, kwargs in (
            ("profile_targets", {"return_value": [("test", self.user_dir)]}),
            ("read_state_value", {"side_effect": lambda config, user, key: self.state.get(key)}),
            ("find_code_cli", {"return_value": "code"}),
            ("run_cli", {"return_value": (0, "")}),
            ("status", {}),
        ):
            mock = patch(f"configure_vscode.{name}", **kwargs)
            setattr(self, name, mock.start())
            self.addCleanup(mock.stop)

    def test_enabled_by_default_with_supported_cached_account(self):
        configure_vscode.sync_settings(self.config, False)
        self.run_cli.assert_called_once_with("code", "--sync", "on")
        self.assertIn("Copilot session uploads are separate", self.status.call_args.args[2])

    def test_config_opt_out_never_requests_sync(self):
        self.config["user"] = {"vscode": {"settingsSync": {"syncAfterSetup": False}}}
        configure_vscode.sync_settings(self.config, False)
        self.read_state_value.assert_not_called()
        self.run_cli.assert_not_called()

    def test_missing_disabled_or_signed_out_state_skips_sync(self):
        cases = (
            {"sync.enable": "false"},
            {"sync.enable": None},
            {"userDataSyncAccountProvider": None},
            {"userDataSyncAccountProvider": "github-enterprise"},
            {"userDataSyncAccountProvider": "microsoft"},
            {"userDataSyncAccountPreference": None},
            {"userDataSyncAccountPreference": " "},
        )
        for change in cases:
            with self.subTest(change=change):
                original = dict(self.state)
                self.state.update(change)
                configure_vscode.sync_settings(self.config, False)
                self.run_cli.assert_not_called()
                self.assertEqual(self.status.call_args.args[0], "skip")
                self.state = original

    def test_microsoft_account_can_be_explicitly_supported(self):
        self.state["userDataSyncAccountProvider"] = "microsoft"
        self.config["user"] = {"vscode": {"settingsSync": {"requiredProvider": "microsoft"}}}
        configure_vscode.sync_settings(self.config, False)
        self.run_cli.assert_called_once()

    def test_dry_run_is_read_only(self):
        configure_vscode.sync_settings(self.config, True)
        self.run_cli.assert_not_called()
        self.assertIn("dry-run", self.status.call_args.args[2])

    def test_missing_cli_skips_sync(self):
        self.find_code_cli.return_value = None
        configure_vscode.sync_settings(self.config, False)
        self.run_cli.assert_not_called()
        self.assertEqual(self.status.call_args.args[0], "skip")

    def test_request_failure_is_reported(self):
        self.run_cli.return_value = (1, "sign-in required")
        configure_vscode.sync_settings(self.config, False)
        self.assertEqual(self.status.call_args.args[0], "warn")
        self.assertIn("sign-in required", self.status.call_args.args[2])

    def test_state_reader_uses_read_only_database_and_warns_on_invalid_state(self):
        db = self.user_dir / "globalStorage" / "state.vscdb"
        self.assertIsNone(self.real_reader({}, self.user_dir, "sync.enable"))
        self.assertFalse(db.exists())
        db.parent.mkdir()
        with closing(sqlite3.connect(db)) as connection:
            connection.execute("CREATE TABLE ItemTable (key TEXT, value TEXT)")
            connection.execute("INSERT INTO ItemTable VALUES ('sync.enable', 'true')")
            connection.commit()
        before = db.read_bytes()
        self.assertEqual(self.real_reader({}, self.user_dir, "sync.enable"), "true")
        self.assertEqual(db.read_bytes(), before)
        db.write_bytes(b"not a sqlite database")
        self.assertIsNone(self.real_reader({}, self.user_dir, "sync.enable"))
        self.assertEqual(self.status.call_args.args[0], "warn")


class SyncOrderingTests(unittest.TestCase):
    def run_main(self, arguments=(), validation_error=False):
        events = []
        config = {"user": {"install": {"devcontainerDefaults": False}}}
        patches = [
            patch.object(sys, "argv", ["configure-vscode.py", *arguments]),
            patch("configure_vscode.load_json", return_value=config),
            patch("configure_vscode.profile_dirs", return_value=[]),
            patch("configure_vscode.status"),
        ]
        for name in ("manage_terminal_instructions", "manage_extensions", "manage_mcp",
                     "manage_copilot_mcp", "validate_install", "sync_settings"):
            def record(*args, name=name):
                events.append(name)
                if name == "validate_install" and validation_error:
                    raise SystemExit("validation failed")
                return True
            patches.append(patch(f"configure_vscode.{name}", side_effect=record))
        for item in patches:
            item.start()
            self.addCleanup(item.stop)
        if validation_error:
            with self.assertRaisesRegex(SystemExit, "validation failed"):
                configure_vscode.main()
        else:
            self.assertEqual(configure_vscode.main(), 0)
        return events

    def test_sync_runs_after_all_managers_and_validation(self):
        self.assertEqual(self.run_main(), [
            "manage_terminal_instructions", "manage_extensions", "manage_mcp",
            "manage_copilot_mcp", "validate_install", "sync_settings",
        ])

    def test_cli_skip_flag_preserves_setup_but_never_requests_sync(self):
        events = self.run_main(["--skip-settings-sync"])
        self.assertIn("validate_install", events)
        self.assertNotIn("sync_settings", events)

    def test_validation_failure_prevents_sync(self):
        self.assertNotIn("sync_settings", self.run_main(validation_error=True))


class TerminalInstructionsTests(unittest.TestCase):
    def test_audit_apply_idempotency_and_preservation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            user_dir = Path(temp_dir)
            path = user_dir / "prompts" / "terminal-execution.instructions.md"
            with patch("configure_vscode.profile_targets", return_value=[("test", user_dir)]):
                configure_vscode.manage_terminal_instructions({}, dry_run=True)
                self.assertFalse(path.exists())
                configure_vscode.manage_terminal_instructions({}, dry_run=False)
                original = path.read_text(encoding="utf-8")
                self.assertIn('applyTo: "**"', original)
                self.assertIn("Never close, reload, or restart VS Code", original)
                self.assertIn("do not wait for them to exit", original)
                before = path.stat().st_mtime_ns
                configure_vscode.manage_terminal_instructions({}, dry_run=False)
                self.assertEqual(path.stat().st_mtime_ns, before)
                path.write_text("User-authored instructions\n", encoding="utf-8")
                configure_vscode.manage_terminal_instructions({}, dry_run=False)
                self.assertEqual(path.read_text(), "User-authored instructions\n")

    def test_disabled_instruction_management_writes_nothing(self):
        with patch("configure_vscode.profile_targets") as targets:
            configure_vscode.manage_terminal_instructions(
                {"user": {"vscode": {"terminalInstructions": {"manage": False}}}},
                dry_run=False,
            )
            targets.assert_not_called()


class CliDeadlineTests(unittest.TestCase):
    def test_default_deadline_is_finite_and_explicit(self):
        with patch("configure_vscode.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "ok", "")
            self.assertEqual(configure_vscode.run_cli("code", "--sync", "on"), (0, "ok"))
            self.assertEqual(run.call_args.kwargs["timeout"], 120)
            self.assertFalse(run.call_args.kwargs["check"])

    def test_actual_timeout_is_not_reported_as_success(self):
        with self.assertRaisesRegex(SystemExit, "exceeded 1s"):
            configure_vscode.run_cli(
                sys.executable, "-c", "import time; time.sleep(5)", timeout=1
            )

    def test_extension_install_has_longer_but_bounded_deadline(self):
        config = {"user": {"vscode": {"extensions": {"install": ["example.extension"]}}}}
        with (
            patch("configure_vscode.code_cli_targets", return_value=[("test", "code", "code")]),
            patch("configure_vscode.installed_extensions", return_value=set()),
            patch("configure_vscode.run_cli", return_value=(0, "")) as run,
        ):
            configure_vscode.manage_extensions(config, dry_run=False)
            self.assertEqual(run.call_args.kwargs["timeout"], 600)
            self.assertFalse(run.call_args.kwargs["capture_output"])


if __name__ == "__main__":
    unittest.main()
