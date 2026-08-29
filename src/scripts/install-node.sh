#!/usr/bin/env bash
#
# Ensures Node.js and npm are available without admin rights or GUI installers.
# The Homebrew formula comes from dev-setup.config.json.
#
# --audit reports what would happen without changing anything.
#
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.sh
. "$script_dir/../config.sh"

audit=0
if [[ "${1:-}" == "--audit" ]]; then
	audit=1
fi

formula="$(devsetup_config advanced.node.homebrewFormula node)"

if command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && npm --version >/dev/null 2>&1; then
	devsetup_status found Node.js "$(node --version) at $(command -v node)"
	devsetup_status found npm "$(npm --version) at $(command -v npm)"
	exit 0
fi

os="$(uname -s 2>/dev/null || printf '%s' "${MSYSTEM:-Windows}")"

if [[ $audit -eq 1 ]]; then
	case "$os" in
		Darwin|Linux)
			if command -v brew >/dev/null 2>&1; then
				devsetup_status install Node.js "would install '$formula' via Homebrew"
			else
				devsetup_status warn Node.js "missing and Homebrew is not installed"
			fi
			;;
		*) devsetup_status warn Node.js "unsupported OS: $os" ;;
	esac
	exit 0
fi

case "$os" in
	Darwin|Linux)
		if ! command -v brew >/dev/null 2>&1; then
			printf 'Node.js/npm unavailable and Homebrew is not installed. Install Node.js LTS from https://nodejs.org/.\n' >&2
			exit 1
		fi
		devsetup_status install Node.js "installing '$formula' via Homebrew"
		brew install "$formula"
		;;
	MINGW*|MSYS*|CYGWIN*)
		printf 'Node.js/npm unavailable in this shell. Run setup.cmd on Windows.\n' >&2
		exit 1
		;;
	*)
		printf 'Unsupported OS: %s\n' "$os" >&2
		exit 1
		;;
esac

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
	printf 'Node.js/npm setup failed. Open a new terminal and run setup again.\n' >&2
	exit 1
fi

devsetup_status found Node.js "$(node --version) at $(command -v node)"
devsetup_status found npm "$(npm --version) at $(command -v npm)"
