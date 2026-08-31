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

DEVSETUP_STATUS_LOG="$(mktemp)"
export DEVSETUP_STATUS_LOG
trap 'rm -f "$DEVSETUP_STATUS_LOG"' EXIT

audit=0
uninstall=0
check_upgrades_only=0
skip_upgrade_check=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--audit) audit=1 ;;
		--uninstall) uninstall=1 ;;
		--check-upgrades-only) check_upgrades_only=1 ;;
		--skip-upgrade-check) skip_upgrade_check=1 ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

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

check_upgrades=1
if [[ $check_upgrades_only -eq 0 ]]; then
	if [[ $skip_upgrade_check -eq 1 ]] || ! devsetup_enabled user.checkUpgrades; then
		check_upgrades=0
	fi
fi
upgrade_flag=""
[[ $check_upgrades -eq 1 ]] && upgrade_flag="--check-upgrades"

if [[ $uninstall -eq 1 ]]; then
	echo "Uninstalling (each step only removes tools this kit manages; Git is never removed):"
	audit_flag=""
	[[ $audit -eq 1 ]] && audit_flag="--audit"
	if devsetup_enabled user.install.git; then "${BASH:-bash}" "$scripts/install-portable-git.sh" --uninstall $audit_flag; fi
	if devsetup_enabled user.install.node; then "${BASH:-bash}" "$scripts/install-node.sh" --uninstall $audit_flag; fi
	if devsetup_enabled user.install.python; then "${BASH:-bash}" "$scripts/install-python.sh" --uninstall $audit_flag; fi
	if devsetup_enabled user.install.php; then "${BASH:-bash}" "$scripts/install-php.sh" --uninstall $audit_flag; fi
	if devsetup_enabled user.install.powershell; then "${BASH:-bash}" "$scripts/install-powershell.sh" --uninstall $audit_flag; fi
	if devsetup_enabled user.install.shellcheck; then "${BASH:-bash}" "$scripts/install-shellcheck.sh" --uninstall $audit_flag; fi
	if devsetup_enabled user.install.gpg; then "${BASH:-bash}" "$scripts/install-gpg.sh" --uninstall $audit_flag; fi
	echo
	if [[ $audit -eq 1 ]]; then
		echo "Uninstall audit complete. Nothing was removed. Re-run with --uninstall (without --audit) to apply."
	else
		echo "Uninstall complete."
	fi
	devsetup_summary "$DEVSETUP_STATUS_LOG" "$audit"
	exit 0
fi

if [[ $check_upgrades_only -eq 1 ]]; then
	echo "Checking for upgrades (detect only - nothing will be installed or changed):"
	if devsetup_enabled user.install.git; then "${BASH:-bash}" "$scripts/install-portable-git.sh" --audit --check-upgrades; fi
	if devsetup_enabled user.install.node; then "${BASH:-bash}" "$scripts/install-node.sh" --audit --check-upgrades; fi
	if devsetup_enabled user.install.python; then "${BASH:-bash}" "$scripts/install-python.sh" --audit --check-upgrades; fi
	if devsetup_enabled user.install.php; then "${BASH:-bash}" "$scripts/install-php.sh" --audit --check-upgrades; fi
	if devsetup_enabled user.install.powershell; then "${BASH:-bash}" "$scripts/install-powershell.sh" --audit --check-upgrades; fi
	if devsetup_enabled user.install.shellcheck; then "${BASH:-bash}" "$scripts/install-shellcheck.sh" --audit --check-upgrades; fi
	if devsetup_enabled user.install.gpg; then "${BASH:-bash}" "$scripts/install-gpg.sh" --audit --check-upgrades; fi
	echo
	echo "Upgrade check complete. Nothing was installed or changed."
	devsetup_summary "$DEVSETUP_STATUS_LOG" 1
	exit 0
fi

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
		git_command="$({ "${BASH:-bash}" "$scripts/install-portable-git.sh" $audit_flag $upgrade_flag --print-path; } | tee /dev/stderr | tail -n 1)"
		if [[ ! -x "$git_command" ]]; then
			git_command=""
		fi
	else
		"${BASH:-bash}" "$scripts/install-portable-git.sh" $audit_flag $upgrade_flag
	fi
else
	devsetup_status skip Git "user.install.git is false"
fi

if [[ -z "$git_command" ]] && command -v git >/dev/null 2>&1; then
	git_command="$(command -v git)"
fi

if devsetup_enabled user.install.node; then
	"${BASH:-bash}" "$scripts/install-node.sh" $audit_flag $upgrade_flag
else
	devsetup_status skip Node.js "user.install.node is false"
fi

python_command=""
if devsetup_enabled user.install.python; then
	if [[ $audit -eq 1 ]]; then
		"${BASH:-bash}" "$scripts/install-python.sh" --audit $upgrade_flag
	else
		python_command="$("${BASH:-bash}" "$scripts/install-python.sh" --print-path $upgrade_flag)"
	fi
else
	devsetup_status skip Python "user.install.python is false"
fi

php_command=""
if devsetup_enabled user.install.php; then
	if [[ $audit -eq 1 ]]; then
		"${BASH:-bash}" "$scripts/install-php.sh" --audit $upgrade_flag
	else
		php_command="$("${BASH:-bash}" "$scripts/install-php.sh" --print-path $upgrade_flag)"
	fi
else
	devsetup_status skip PHP "user.install.php is false"
fi

powershell_command=""
if devsetup_enabled user.install.powershell; then
	if [[ $audit -eq 1 ]]; then
		"${BASH:-bash}" "$scripts/install-powershell.sh" --audit $upgrade_flag
	else
		powershell_command="$("${BASH:-bash}" "$scripts/install-powershell.sh" --print-path $upgrade_flag)"
	fi
else
	devsetup_status skip PowerShell "user.install.powershell is false"
fi

if devsetup_enabled user.install.shellcheck; then
	"${BASH:-bash}" "$scripts/install-shellcheck.sh" $audit_flag $upgrade_flag
else
	devsetup_status skip ShellCheck "user.install.shellcheck is false"
fi

if devsetup_enabled user.install.gpg; then
	# Unlike the other Homebrew installers, GPG is more prone to environment-specific
	# failures, so a failure here shouldn't abort the rest of setup (set -e otherwise would).
	if ! "${BASH:-bash}" "$scripts/install-gpg.sh" $audit_flag $upgrade_flag; then
		devsetup_status warn GPG "install-gpg.sh failed; see the message above"
	fi
else
	devsetup_status skip GPG "user.install.gpg is false"
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
	echo "Setup complete."
fi

devsetup_summary "$DEVSETUP_STATUS_LOG" "$audit"
