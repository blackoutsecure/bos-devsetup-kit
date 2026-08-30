#!/usr/bin/env bash
#
# Ensures PHP is available for VS Code's built-in PHP validator.
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

formula="$(devsetup_config advanced.php.homebrewFormula php)"
php_command=""
if command -v php >/dev/null 2>&1 && php --version >/dev/null 2>&1; then
	php_command="$(command -v php)"
fi

if [[ $audit -eq 1 ]]; then
	if [[ -n "$php_command" ]]; then
		devsetup_status found PHP "$("$php_command" --version | head -n 1) at $php_command"
	elif command -v brew >/dev/null 2>&1; then
		devsetup_status install PHP "would install '$formula' via Homebrew"
	else
		devsetup_status warn PHP "missing and Homebrew is not installed"
	fi
	exit 0
fi

if [[ -z "$php_command" ]]; then
	os="$(uname -s 2>/dev/null || printf '%s' "${MSYSTEM:-Windows}")"
	if [[ "$os" != "Darwin" && "$os" != "Linux" ]]; then
		printf 'PHP setup is unsupported on %s.\n' "$os" >&2
		exit 1
	fi
	if ! devsetup_ensure_homebrew; then
		printf 'PHP is unavailable and Homebrew could not be installed. Install PHP from https://www.php.net/downloads.php.\n' >&2
		exit 1
	fi
	devsetup_status install PHP "installing '$formula' via Homebrew" >&2
	NONINTERACTIVE=1 brew install "$formula" < /dev/null >&2
	php_command="$(command -v php || true)"
fi

if [[ -z "$php_command" ]] || ! "$php_command" --version >/dev/null 2>&1; then
	printf 'PHP setup failed. Open a new terminal and run setup again.\n' >&2
	exit 1
fi

if [[ $print_path -eq 1 ]]; then
	devsetup_status found PHP "$("$php_command" --version | head -n 1) at $php_command" >&2
	printf '%s\n' "$php_command"
else
	devsetup_status found PHP "$("$php_command" --version | head -n 1) at $php_command"
fi
