#!/usr/bin/env bash
#
# Ensures PowerShell is available for VS Code's PowerShell extension.
# --print-path prints only the executable path on stdout; --audit changes nothing.
#
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=src/config.sh
. "$script_dir/../config.sh"

print_path=0
audit=0
uninstall=0
check_upgrades=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--print-path) print_path=1 ;;
		--audit) audit=1 ;;
		--uninstall) uninstall=1 ;;
		--check-upgrades) check_upgrades=1 ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

formula="$(devsetup_config advanced.powershell.homebrewFormula powershell)"

if [[ $uninstall -eq 1 ]]; then
	devsetup_uninstall_via_homebrew PowerShell "$formula" "$audit" || true
	exit 0
fi

devsetup_install_via_homebrew PowerShell "$formula" pwsh \
	"Install it from https://learn.microsoft.com/powershell/." "$audit" "$print_path" "$check_upgrades"
