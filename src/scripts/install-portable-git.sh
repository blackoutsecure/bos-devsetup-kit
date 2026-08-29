#!/usr/bin/env bash
#
# Ensures a usable Git is available without requiring sudo/admin rights, then
# applies the configured credential helper and (if set) the git identity.
#
# macOS: git ships with Xcode Command Line Tools; Apple requires its
#        installer UI if the tools are missing.
# Linux: prefers an existing git on PATH; falls back to installing
#        Homebrew for Linux (linuxbrew, installs entirely under $HOME,
#        no root required) and using it to install git.
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

os="$(uname -s)"
formula="$(devsetup_config advanced.git.homebrewFormula git)"

if command -v git >/dev/null 2>&1; then
	devsetup_status found Git "$(git --version) at $(command -v git)"
	git_present=1
else
	git_present=0
fi

if [[ $audit -eq 1 ]]; then
	if [[ $git_present -eq 0 ]]; then
		case "$os" in
			Darwin) devsetup_status warn Git "missing; run xcode-select --install once" ;;
			Linux)  devsetup_status install Git "would install '$formula' via Homebrew" ;;
		esac
	fi
	user_email="$(devsetup_config user.git.userEmail "")"
	devsetup_git_identity_status 1
	exit 0
fi

if [[ $git_present -eq 0 ]]; then
	case "$os" in
		Darwin)
			if ! xcode-select -p >/dev/null 2>&1; then
				devsetup_status warn Git "missing; macOS requires 'xcode-select --install' once"
				exit 1
			fi
			echo "Git was not found even though Xcode Command Line Tools are present." >&2
			exit 1
			;;
		Linux)
			devsetup_status install Git "installing '$formula' via Homebrew"
			if ! command -v brew >/dev/null 2>&1; then
				brew_install_url="$(devsetup_config advanced.git.homebrewInstallUrl https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
				brew_shellenv="$(devsetup_config advanced.git.linuxbrewShellenv /home/linuxbrew/.linuxbrew/bin/brew)"
				NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$brew_install_url")"
				eval "$("$brew_shellenv" shellenv)"
			fi
			brew install "$formula"
			devsetup_status found Git "$(git --version) at $(command -v git)"
			;;
		*)
			echo "Unsupported OS: $os" >&2
			exit 1
			;;
	esac
fi

case "$os" in
	Darwin) helper="$(devsetup_config advanced.git.credential.macos.helper osxkeychain)" ;;
	*)      helper="$(devsetup_config advanced.git.credential.linux.helper manager)" ;;
esac

if [[ "$(git config --global --get credential.helper 2>/dev/null || true)" == "$helper" ]]; then
	devsetup_status found "git cfg" "credential helper already '$helper'"
elif command -v "git-credential-$helper" >/dev/null 2>&1; then
	git config --global credential.helper "$helper"
	devsetup_status install "git cfg" "credential helper set to '$helper'"
else
	devsetup_status skip "git cfg" "credential helper '$helper' is not installed"
fi

user_name="$(devsetup_config user.git.userName "")"
user_email="$(devsetup_config user.git.userEmail "")"
# Plain ifs, not && chains: an empty value would trip set -e.
if [[ -n "$user_name" ]]; then
	git config --global user.name "$user_name"
fi
if [[ -n "$user_email" ]]; then
	git config --global user.email "$user_email"
fi
devsetup_git_identity_status
