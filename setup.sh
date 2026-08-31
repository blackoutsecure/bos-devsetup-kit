#!/usr/bin/env bash
#
# macOS / Linux entry point. Delegates to the dedicated installers rather than
# duplicating their logic, then applies VS Code settings last.
# Windows uses setup.cmd -> setup.ps1.
#
# --audit detects everything and reports what would happen, changing nothing.
#
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=src/config.sh
. "$script_dir/src/config.sh"
scripts="$script_dir/src/scripts"

audit=0
if [[ "${1:-}" == "--audit" ]]; then
	audit=1
fi

os="$(uname -s 2>/dev/null || printf '%s' "${MSYSTEM:-Windows}")"
case "$os" in
	MINGW*|MSYS*|CYGWIN*)
		printf 'Run setup.cmd on Windows; it uses the PowerShell path.\n' >&2
		exit 1
		;;
	Darwin|Linux) ;;
	*)
		printf 'Unsupported OS: %s\n' "$os" >&2
		exit 1
		;;
esac

if [[ $audit -eq 1 ]]; then
	echo "Auditing (detect only - nothing will be installed or changed):"
	audit_flag="--audit"
else
	echo "Running setup (each step is skipped when already satisfied):"
	audit_flag=""
fi

git_command=""
if devsetup_enabled user.install.git; then
	if devsetup_enabled user.install.vscodeSettings; then
		git_command="$({ "${BASH:-bash}" "$scripts/install-portable-git.sh" $audit_flag --print-path; } | tee /dev/stderr | tail -n 1)"
		if [[ ! -x "$git_command" ]]; then
			git_command=""
		fi
	else
		"${BASH:-bash}" "$scripts/install-portable-git.sh" $audit_flag
	fi
else
	devsetup_status skip Git "user.install.git is false"
fi

if [[ -z "$git_command" ]] && command -v git >/dev/null 2>&1; then
	git_command="$(command -v git)"
fi

if devsetup_enabled user.install.node; then
	"${BASH:-bash}" "$scripts/install-node.sh" $audit_flag
else
	devsetup_status skip Node.js "user.install.node is false"
fi

python_command=""
if devsetup_enabled user.install.python; then
	if [[ $audit -eq 1 ]]; then
		"${BASH:-bash}" "$scripts/install-python.sh" --audit
	else
		python_command="$("${BASH:-bash}" "$scripts/install-python.sh" --print-path)"
	fi
else
	devsetup_status skip Python "user.install.python is false"
fi

php_command=""
if devsetup_enabled user.install.php; then
	if [[ $audit -eq 1 ]]; then
		"${BASH:-bash}" "$scripts/install-php.sh" --audit
	else
		php_command="$("${BASH:-bash}" "$scripts/install-php.sh" --print-path)"
	fi
else
	devsetup_status skip PHP "user.install.php is false"
fi

powershell_command=""
if devsetup_enabled user.install.powershell; then
	if [[ $audit -eq 1 ]]; then
		"${BASH:-bash}" "$scripts/install-powershell.sh" --audit
	else
		powershell_command="$("${BASH:-bash}" "$scripts/install-powershell.sh" --print-path)"
	fi
else
	devsetup_status skip PowerShell "user.install.powershell is false"
fi

if devsetup_enabled user.install.shellcheck; then
	"${BASH:-bash}" "$scripts/install-shellcheck.sh" $audit_flag
else
	devsetup_status skip ShellCheck "user.install.shellcheck is false"
fi

if [[ -z "$python_command" ]]; then
	for candidate in python3 python; do
		if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version >/dev/null 2>&1; then
			python_command="$(command -v "$candidate")"
			break
		fi
	done
fi

if devsetup_enabled user.install.vscodeSettings; then
	if [[ -n "$python_command" ]]; then
		vscode_args=(--config "$DEVSETUP_CONFIG_FILE" --python-path "$python_command")
		if [[ -n "$git_command" ]]; then
			vscode_args+=(--git-path "$git_command")
		fi
		if [[ -n "$php_command" ]]; then
			vscode_args+=(--php-path "$php_command")
		fi
		if [[ -n "$powershell_command" ]]; then
			vscode_args+=(--powershell-path "$powershell_command")
		fi
		if [[ $audit -eq 1 ]]; then
			"$python_command" "$script_dir/src/configure-vscode.py" "${vscode_args[@]}" --dry-run
		else
			"$python_command" "$script_dir/src/configure-vscode.py" "${vscode_args[@]}"
		fi
	else
		devsetup_status warn vscode "Python not available; run src/configure-vscode.py manually"
	fi
else
	devsetup_status skip vscode "user.install.vscodeSettings is false"
fi

echo
if [[ $audit -eq 1 ]]; then
	echo "Audit complete. Nothing was installed or changed. Re-run without --audit to apply."
else
	echo "Setup complete. WSL was not installed or invoked."
	if devsetup_enabled user.install.vscodeSettings; then
		echo "VS Code settings were validated. Settings Sync was not requested unless enabled in config."
	fi
fi
