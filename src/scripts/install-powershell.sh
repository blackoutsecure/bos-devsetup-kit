#!/usr/bin/env bash
#
# Ensures PowerShell is available for VS Code's PowerShell extension.
# --print-path prints only the executable path on stdout; --audit changes nothing.
#
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.sh
. "$script_dir/../config.sh"

mode="${1:-}"
print_path=0
audit=0
case "$mode" in
	--print-path) print_path=1 ;;
	--audit) audit=1 ;;
esac

formula="$(devsetup_config advanced.powershell.homebrewFormula powershell)"
command_path=""
if command -v pwsh >/dev/null 2>&1 && pwsh --version >/dev/null 2>&1; then
	command_path="$(command -v pwsh)"
fi

if [[ $audit -eq 1 ]]; then
	if [[ -n "$command_path" ]]; then
		devsetup_status found PowerShell "$("$command_path" --version) at $command_path"
	elif command -v brew >/dev/null 2>&1; then
		devsetup_status install PowerShell "would install '$formula' via Homebrew"
	else
		devsetup_status warn PowerShell "missing and Homebrew is not installed"
	fi
	exit 0
fi

if [[ -z "$command_path" ]]; then
	os="$(uname -s 2>/dev/null || printf '%s' "${MSYSTEM:-Windows}")"
	if [[ "$os" != "Darwin" && "$os" != "Linux" ]]; then
		printf 'PowerShell setup is unsupported on %s.\n' "$os" >&2
		exit 1
	fi
	if ! devsetup_ensure_homebrew; then
		printf 'PowerShell is unavailable and Homebrew could not be installed. Install it from https://learn.microsoft.com/powershell/.\n' >&2
		exit 1
	fi
	devsetup_status install PowerShell "installing '$formula' via Homebrew" >&2
	brew install "$formula" >&2
	command_path="$(command -v pwsh || true)"
fi

if [[ -z "$command_path" ]] || ! "$command_path" --version >/dev/null 2>&1; then
	printf 'PowerShell setup failed. Open a new terminal and run setup again.\n' >&2
	exit 1
fi

if [[ $print_path -eq 1 ]]; then
	devsetup_status found PowerShell "$("$command_path" --version) at $command_path" >&2
	printf '%s\n' "$command_path"
else
	devsetup_status found PowerShell "$("$command_path" --version) at $command_path"
fi
