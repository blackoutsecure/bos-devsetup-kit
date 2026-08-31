#!/usr/bin/env bash
# Ensures ShellCheck is available for local Bash linting.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.sh
. "$script_dir/../config.sh"

audit=0
if [[ "${1:-}" == "--audit" ]]; then audit=1; fi

formula="$(devsetup_config advanced.shellcheck.homebrewFormula shellcheck)"
command_path="$(command -v shellcheck || true)"

if [[ $audit -eq 1 ]]; then
	if [[ -n "$command_path" ]]; then
		devsetup_status found ShellCheck "$("$command_path" --version | head -n 1) at $command_path"
	elif command -v brew >/dev/null 2>&1; then
		devsetup_status install ShellCheck "would install '$formula' via Homebrew"
	else
		devsetup_status warn ShellCheck "missing and Homebrew is not installed"
	fi
	exit 0
fi

if [[ -z "$command_path" ]]; then
	if ! devsetup_ensure_homebrew; then
		printf 'ShellCheck is unavailable and Homebrew could not be installed. Install it from https://www.shellcheck.net/.\n' >&2
		exit 1
	fi
	devsetup_status install ShellCheck "installing '$formula' via Homebrew (live output below, may take a few minutes)"
	NONINTERACTIVE=1 brew install "$formula"
	command_path="$(command -v shellcheck || true)"
fi

if [[ -z "$command_path" ]]; then
	printf 'ShellCheck setup failed. Open a new terminal and run setup again.\n' >&2
	exit 1
fi
devsetup_status found ShellCheck "$("$command_path" --version | head -n 1) at $command_path"