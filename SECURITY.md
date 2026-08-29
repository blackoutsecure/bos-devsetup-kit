# Security Policy

## Supported Versions

We support the latest major release tag (e.g. `v1`) and the most recent patch versions. Older tags may receive critical fixes only.

## Reporting a Vulnerability

Please use GitHub Security Advisories ("Report a vulnerability" button in the repository) for confidential disclosure. Provide:

- Affected version/tag and platform (Windows/macOS/Linux)
- Description of the issue and potential impact
- Steps to reproduce (minimal example, including relevant `config/dev-setup.config.json` values)
- Suggested fix (if available)

Do NOT open a public issue for sensitive security problems.

## Response Process

1. Triage within 5 business days.
2. Reproduce and assess severity.
3. Patch and create a prerelease for validation if needed.
4. Publish fixed tag and coordinated security advisory.

## Scope

This kit installs developer tooling (Git, Node.js, Python) and writes VS Code settings, extensions,
and MCP server configuration to the local user profile. It requires no administrator or root access
and does not run as a service or listen on any network port. Network access is limited to package
manager registries (`winget`, Homebrew, `npm`), the Git for Windows release API, and the VS Code
extension marketplace.

## Safe Handling Recommendations

- Run `-Audit` / `--audit` before a real run on any machine you do not fully control.
- Review `user.mcp.servers` before applying — MCP servers can execute local commands (`npx`, `uvx`)
  or reach network endpoints. Only add servers you trust.
- Keep `user.git.userEmail` and other identity values out of shared/forked config files if you do
  not want them applied to someone else's machine.

## Preferred Contact

If GitHub advisories are not available, open an issue with the prefix `[SECURITY]` requesting a private communication channel.
