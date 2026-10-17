import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
