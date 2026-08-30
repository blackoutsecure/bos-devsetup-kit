#!/usr/bin/env bash
#
# Sourceable config reader for dev-setup.
#
#   . "$(dirname "$0")/../config.sh"
#   version="$(devsetup_config user.python.version 3.14)"
#
# Reads the config with python3, python, or jq - whichever exists. The config is
# needed before Python is installed, so every lookup falls back to the
# caller-supplied default rather than failing.
#
# DEVSETUP_ROOT is the repository root, resolved from this file's location.

DEVSETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVSETUP_CONFIG_FILE="${DEVSETUP_CONFIG_FILE:-$DEVSETUP_ROOT/config/dev-setup.config.json}"

# The reader is resolved once, here at source time, which runs in the caller's
# shell. Every devsetup_config call happens inside a $( ) subshell, so a value
# cached during a lookup would be discarded; only a value set at source time is
# inherited. A plain variable rather than an associative array keeps this
# working on macOS's bash 3.2.
DEVSETUP_READER=""
for _devsetup_candidate in python3 python; do
	if command -v "$_devsetup_candidate" >/dev/null 2>&1 &&
		"$_devsetup_candidate" --version >/dev/null 2>&1; then
		DEVSETUP_READER="$_devsetup_candidate"
		break
	fi
done
if [[ -z "$DEVSETUP_READER" ]] && command -v jq >/dev/null 2>&1; then
	DEVSETUP_READER="jq"
fi
unset _devsetup_candidate

devsetup_config_reader() {
	[[ -n "$DEVSETUP_READER" ]] || return 1
	printf '%s' "$DEVSETUP_READER"
}

devsetup_config() {
	local key="$1"
	local default="${2-}"
	local value

	if [[ ! -f "$DEVSETUP_CONFIG_FILE" || -z "$DEVSETUP_READER" ]]; then
		printf '%s' "$default"
		return 0
	fi

	if [[ "$DEVSETUP_READER" == "jq" ]]; then
		value="$(jq -r --arg k "$key" '
			reduce ($k | split(".")[]) as $s (.; if type == "object" then .[$s] else null end)
			| if . == null then empty
			  elif type == "array" then .[] | tostring
			  else tostring end
		' "$DEVSETUP_CONFIG_FILE" 2>/dev/null)" || value=""
	else
		value="$("$DEVSETUP_READER" -c '
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    node = json.load(open(path, encoding="utf-8"))
except Exception:
    sys.exit(1)
for segment in key.split("."):
    if not isinstance(node, dict) or segment not in node:
        sys.exit(1)
    node = node[segment]
if node is None:
    sys.exit(1)
if isinstance(node, bool):
    print("true" if node else "false")
elif isinstance(node, list):
    print("\n".join(str(item) for item in node))
else:
    print(node)
' "$DEVSETUP_CONFIG_FILE" "$key" 2>/dev/null)" || value=""
	fi

	# Empty means unset in the config; fall back like the PowerShell loader does.
	if [[ -z "$value" ]]; then
		printf '%s' "$default"
	else
		printf '%s' "$value"
	fi
}

devsetup_enabled() {
	[[ "$(devsetup_config "$1" "${2:-true}")" == "true" ]]
}

devsetup_ensure_homebrew() {
	if command -v brew >/dev/null 2>&1; then
		return 0
	fi
	if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
		return 1
	fi

	brew_install_url="$(devsetup_config advanced.git.homebrewInstallUrl https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	brew_shellenv="$(devsetup_config advanced.git.linuxbrewShellenv /home/linuxbrew/.linuxbrew/bin/brew)"
	devsetup_status install Homebrew "bootstrapping via official installer (no existing output for a few seconds is normal)" >&2
	NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$brew_install_url")"
	if [[ ! -x "$brew_shellenv" ]]; then
		return 1
	fi
	eval "$("$brew_shellenv" shellenv)"
	command -v brew >/dev/null 2>&1
}

# One audit line per component so a run reads as a report.
#   found   - already present, nothing to do
#   install - something is about to change
#   skip    - disabled in config, or not applicable on this platform
#   warn    - proceeded, but the result is degraded
devsetup_status() {
	printf '  %-9s %-8s %s\n' "[$1]" "$2" "${3-}"
}

# Reports git identity state identically in audit and apply runs.
# Usage: devsetup_git_identity_status [audit]
devsetup_git_identity_status() {
	local audit="${1:-0}" configured current verb
	configured="$(devsetup_config user.git.userEmail "")"
	current="$(git config --global --get user.email 2>/dev/null || true)"

	if [[ -n "$configured" ]]; then
		if [[ "$audit" == "1" ]]; then verb="would apply"; else verb="applied"; fi
		devsetup_status install identity "$verb $configured from config"
	elif [[ -n "$current" ]]; then
		devsetup_status found identity "already set to $current"
	else
		devsetup_status warn identity "not set; fill user.git.userName / user.git.userEmail"
	fi
}
