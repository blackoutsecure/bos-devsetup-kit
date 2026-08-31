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

# Shared single-command Homebrew install pattern for install-php.sh,
# install-powershell.sh, and install-shellcheck.sh, which differ only in
# component name, formula, and command to look for.
#   $1 component name   $2 formula        $3 command to look for on PATH
#   $4 manual-install hint (used on failure)
#   $5 audit (0/1)      $6 print-path (0/1, default 0)  $7 check-upgrades (0/1, default 0)
# Prints the resolved command path on stdout when print-path is requested.
devsetup_install_via_homebrew() {
	local component="$1" formula="$2" command_name="$3" manual_hint="$4" audit="$5" print_path="${6:-0}" check_upgrades="${7:-0}"
	local command_path=""
	if command -v "$command_name" >/dev/null 2>&1 && "$command_name" --version >/dev/null 2>&1; then
		command_path="$(command -v "$command_name")"
	fi

	if [[ "$audit" -eq 1 ]]; then
		if [[ -n "$command_path" ]]; then
			devsetup_status found "$component" "$("$command_path" --version 2>&1 | head -n 1) at $command_path"
			[[ "$check_upgrades" -eq 1 ]] && devsetup_check_homebrew_upgrade "$component" "$formula"
		elif command -v brew >/dev/null 2>&1; then
			devsetup_status install "$component" "would install '$formula' via Homebrew"
		else
			devsetup_status warn "$component" "missing and Homebrew is not installed"
		fi
		return 0
	fi

	if [[ -z "$command_path" ]]; then
		local os
		os="$(uname -s 2>/dev/null || printf '%s' "${MSYSTEM:-Windows}")"
		if [[ "$os" != "Darwin" && "$os" != "Linux" ]]; then
			printf '%s setup is unsupported on %s.\n' "$component" "$os" >&2
			return 1
		fi
		if ! devsetup_ensure_homebrew; then
			printf '%s is unavailable and Homebrew could not be installed. %s\n' "$component" "$manual_hint" >&2
			return 1
		fi
		devsetup_status install "$component" "installing '$formula' via Homebrew (live output below, may take a few minutes)" >&2
		NONINTERACTIVE=1 brew install "$formula" < /dev/null >&2
		command_path="$(command -v "$command_name" || true)"
	fi

	if [[ -z "$command_path" ]] || ! "$command_path" --version >/dev/null 2>&1; then
		printf '%s setup failed. Open a new terminal and run setup again.\n' "$component" >&2
		return 1
	fi

	if [[ "$print_path" -eq 1 ]]; then
		devsetup_status found "$component" "$("$command_path" --version 2>&1 | head -n 1) at $command_path" >&2
		printf '%s\n' "$command_path"
	else
		devsetup_status found "$component" "$("$command_path" --version 2>&1 | head -n 1) at $command_path"
	fi
	[[ "$check_upgrades" -eq 1 ]] && devsetup_check_homebrew_upgrade "$component" "$formula"
	return 0
}

# Reports (never applies) whether Homebrew has a newer version of a formula.
# Silent when Homebrew is unavailable or the formula is already current.
devsetup_check_homebrew_upgrade() {
	local component="$1" formula="$2" outdated
	command -v brew >/dev/null 2>&1 || return 0
	outdated="$(brew outdated --formula "$formula" 2>/dev/null || true)"
	if [[ -n "$outdated" ]]; then
		devsetup_status update "$component" "newer version available (run: brew upgrade $formula)"
	fi
}

# Removes a Homebrew-managed formula. Only ever called when --uninstall is passed explicitly.
devsetup_uninstall_via_homebrew() {
	local component="$1" formula="$2" audit="${3:-0}"
	if ! command -v brew >/dev/null 2>&1; then
		devsetup_status warn "$component" "Homebrew is unavailable; cannot uninstall"
		return 1
	fi
	if [[ "$audit" -eq 1 ]]; then
		devsetup_status remove "$component" "would uninstall '$formula' via Homebrew"
		return 0
	fi
	if brew uninstall --formula "$formula" >/dev/null 2>&1; then
		devsetup_status remove "$component" "uninstalled '$formula' via Homebrew"
	else
		devsetup_status warn "$component" "not installed via Homebrew, or uninstall failed"
	fi
}

# One audit line per component so a run reads as a report.
#   found   - already present, nothing to do
#   install - something is about to change
#   skip    - disabled in config, or not applicable on this platform
#   warn    - proceeded, but the result is degraded
#   update  - a newer version is available (reported only, never applied automatically)
#   remove  - uninstalled, only reachable via --uninstall
#
# Colors honour the de-facto NO_COLOR standard (https://no-color.org) and
# only render when the destination is a TTY or the GitHub Actions log
# surface, matching the palette bos-code-scanning-kit uses for severities.
_DEVSETUP_RESET=$'\033[0m'
devsetup__color_enabled() {
	[[ -n "${NO_COLOR:-}" ]] && return 1
	[[ "${GITHUB_ACTIONS:-}" == "true" ]] && return 0
	[[ -t 1 ]]
}

devsetup_status() {
	local state="$1" component="$2" detail="${3-}" color="" tag
	case "$state" in
		found) color=$'\033[32m' ;;   # green   - already satisfied
		install) color=$'\033[36m' ;; # cyan    - change in progress
		warn) color=$'\033[33m' ;;    # yellow  - degraded but proceeded
		skip) color=$'\033[90m' ;;    # grey    - disabled or n/a
		update) color=$'\033[35m' ;;  # magenta - newer version available
		remove) color=$'\033[31m' ;;  # red     - uninstalled via --uninstall
	esac
	tag="$(printf '%-9s' "[$state]")"
	if [[ -n "$color" ]] && devsetup__color_enabled; then
		tag="${color}${tag}${_DEVSETUP_RESET}"
	fi
	printf '  %s %-8s %s\n' "$tag" "$component" "$detail"

	# DEVSETUP_STATUS_LOG lets the top-level runner tally every line, including
	# ones from install-*.sh scripts that run as separate bash processes and
	# ones emitted by configure-vscode.py.
	if [[ -n "${DEVSETUP_STATUS_LOG:-}" ]]; then
		printf '%s|%s|%s\n' "$state" "$component" "$detail" >> "$DEVSETUP_STATUS_LOG"
	fi
}

# Prints one total per status tag for the whole run, reading whatever
# devsetup_status calls (from any process) logged to DEVSETUP_STATUS_LOG. In
# --audit runs, also recommends whether to run the real setup, lists what it
# would change, and gives the exact command.
devsetup_summary() {
	local log_path="${1:-}" audit="${2:-0}" found=0 install=0 skip=0 warn=0 update=0 remove=0
	local warn_label install_label summary_line update_label
	if [[ -n "$log_path" && -f "$log_path" ]]; then
		found="$(grep -c '^found|' "$log_path" || true)"
		install="$(grep -c '^install|' "$log_path" || true)"
		skip="$(grep -c '^skip|' "$log_path" || true)"
		warn="$(grep -c '^warn|' "$log_path" || true)"
		update="$(grep -c '^update|' "$log_path" || true)"
		remove="$(grep -c '^remove|' "$log_path" || true)"
	fi
	warn_label="warnings"
	[[ "$warn" -eq 1 ]] && warn_label="warning"
	install_label="installed"
	[[ "$audit" -eq 1 ]] && install_label="would install"
	echo
	summary_line="Summary: $found found, $install $install_label, $skip skipped, $warn $warn_label"
	if [[ "$update" -gt 0 ]]; then
		update_label="updates"
		[[ "$update" -eq 1 ]] && update_label="update"
		summary_line="$summary_line, $update $update_label available"
	fi
	if [[ "$remove" -gt 0 ]]; then
		summary_line="$summary_line, $remove removed"
	fi
	echo "$summary_line"

	if [[ "$audit" -eq 1 ]]; then
		echo
		if [[ "$install" -eq 0 ]]; then
			echo "Recommendation: no changes needed, environment already matches config/dev-setup.config.json. No need to run without --audit."
		else
			echo "Recommendation: $install change(s) would be made if you run the real setup:"
			grep '^install|' "$log_path" | while IFS='|' read -r _ component detail; do
				echo "  - ${component}: ${detail}"
			done
			echo "Run this to apply them: ./setup.sh"
		fi
		if [[ "$warn" -gt 0 ]]; then
			echo "$warn item(s) need attention regardless (see [warn] lines above)."
		fi
	fi
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
