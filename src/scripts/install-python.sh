#!/usr/bin/env bash
#
# Ensures Python is available without admin rights or GUI installers.
# Version and uv download URL come from dev-setup.config.json.
#
#   --print-path  print only the interpreter path on stdout (progress to stderr)
#   --audit       report what would happen without changing anything
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

python_version="$(devsetup_config user.python.version 3.14)"
uv_install_url="$(devsetup_config advanced.python.uvInstallUrl.unix https://astral.sh/uv/install.sh)"

python_command=""
for candidate in python3 python; do
	if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version >/dev/null 2>&1; then
		python_command="$(command -v "$candidate")"
		break
	fi
done

if [[ $audit -eq 1 ]]; then
	if [[ -n "$python_command" ]]; then
		devsetup_status found Python "$("$python_command" --version 2>&1) at $python_command"
	elif command -v uv >/dev/null 2>&1; then
		devsetup_status install Python "would install CPython $python_version via uv"
	else
		devsetup_status install Python "would bootstrap uv, then install CPython $python_version"
	fi
	exit 0
fi

if [[ -z "$python_command" ]]; then
	if ! command -v uv >/dev/null 2>&1; then
		devsetup_status install uv "installing to \$HOME/.local/bin (user-local, no admin, no GUI)" >&2
		uv_installer="$HOME/.uv-install.sh"
		curl -LsSf "$uv_install_url" -o "$uv_installer"
		"${BASH:-bash}" "$uv_installer" >&2
		rm -f "$uv_installer"
		export PATH="$HOME/.local/bin:$PATH"
	fi
	if ! command -v uv >/dev/null 2>&1; then
		echo "Python is unavailable and uv could not be installed automatically. Install uv from https://docs.astral.sh/uv/. No GUI installer was launched." >&2
		exit 1
	fi
	devsetup_status install Python "installing CPython $python_version via uv" >&2
	uv python install "$python_version" >&2
	python_command="$(uv python find "$python_version")"
fi

if [[ $print_path -eq 1 ]]; then
	devsetup_status found Python "$("$python_command" --version 2>&1) at $python_command" >&2
	printf '%s\n' "$python_command"
else
	devsetup_status found Python "$("$python_command" --version 2>&1) at $python_command"
fi
