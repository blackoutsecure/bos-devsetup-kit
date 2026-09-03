#!/usr/bin/env bash
#
# Ensures Homebrew is installed without admin rights.
# On macOS, Homebrew is typically pre-installed or installable by users.
# On Linux, Homebrew is installed to $HOME/.linuxbrew automatically.
#
# --audit reports what would happen without changing anything.
#
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../config.sh
. "$script_dir/../config.sh"

audit=0
uninstall=0
check_upgrades=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--audit) audit=1 ;;
		--uninstall) uninstall=1 ;;
		--check-upgrades) check_upgrades=1 ;;
		*) echo "Unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

os="$(uname -s 2>/dev/null || printf '%s' "${MSYSTEM:-Windows}")"

case "$os" in
	MINGW*|MSYS*|CYGWIN*)
		# Homebrew is not available on Windows; this is expected
		exit 0
		;;
	Darwin|Linux) ;;
	*)
		printf 'Homebrew setup is unsupported on %s.\n' "$os" >&2
		return 1
		;;
esac

if [[ $uninstall -eq 1 ]]; then
	# Homebrew should not be uninstalled as it manages many tools installed by other scripts
	devsetup_status skip Homebrew "Homebrew is not uninstalled (other tools depend on it)"
	exit 0
fi

if command -v brew >/dev/null 2>&1; then
	devsetup_status found Homebrew "$(brew --version | head -n 1) at $(command -v brew)"
	exit 0
fi

if [[ $audit -eq 1 ]]; then
	case "$os" in
		Darwin)
			devsetup_status install Homebrew "would install via official macOS installer (requires curl)"
			;;
		Linux)
			devsetup_status install Homebrew "would install via official Linux installer to \$HOME/.linuxbrew (requires curl)"
			;;
	esac
	exit 0
fi

# Not found and not auditing, so attempt installation
if ! devsetup_ensure_homebrew; then
	printf 'Homebrew installation failed. Please install Homebrew manually:\n' >&2
	case "$os" in
		Darwin)
			printf '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n' >&2
			;;
		Linux)
			printf '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n' >&2
			;;
	esac
	exit 1
fi

if command -v brew >/dev/null 2>&1; then
	devsetup_status found Homebrew "$(brew --version | head -n 1) at $(command -v brew)"
	exit 0
else
	printf 'Homebrew installation succeeded but "brew" command is not on PATH. Please open a new terminal.\n' >&2
	exit 1
fi
