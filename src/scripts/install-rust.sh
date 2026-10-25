#!/usr/bin/env bash
# Provisions stable Rust without changing an existing default toolchain.
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
case "$(uname -s)" in
	Darwin|Linux) ;;
	*) devsetup_status warn Rust "run setup.cmd on Windows"; exit 1 ;;
esac
if [[ $uninstall -eq 1 ]]; then
	devsetup_status skip Rust "shared rustup toolchains and Cargo packages are preserved; remove manually with rustup self uninstall if intended"
	exit 0
fi

formula="$(devsetup_config advanced.rust.homebrewFormula rustup)"
cargo_bin="${CARGO_HOME:-$HOME/.cargo}/bin"
rustup="$(command -v rustup || true)"
if [[ -z "$rustup" && -x "$cargo_bin/rustup" ]]; then rustup="$cargo_bin/rustup"; fi
brew_path="$(devsetup_homebrew_path || true)"
rustup_bin=""
if [[ -n "$brew_path" ]]; then
	rustup_bin="$("$brew_path" --prefix)/opt/$formula/bin"
	if [[ -z "$rustup" && -x "$rustup_bin/rustup" ]]; then rustup="$rustup_bin/rustup"; fi
fi
if [[ -z "$rustup" ]]; then
	if [[ $audit -eq 1 ]]; then
		devsetup_status install Rust "would install $formula via Homebrew and stable with rustfmt, clippy, rust-src"
		devsetup_status skip "Rust build" "linker readiness is unverified; audit does not compile or run code"
		exit 0
	fi
	devsetup_ensure_homebrew
	rustup_bin="$(brew --prefix)/opt/$formula/bin"
	export PATH="$rustup_bin:$cargo_bin:$PATH"
	devsetup_install_via_homebrew rustup "$formula" rustup "Install rustup from https://rustup.rs/." 0
	rustup="$(command -v rustup)"
fi
toolchains="$("$rustup" toolchain list)"
if ! printf '%s\n' "$toolchains" | grep -Eq '^stable(-|[[:space:]]|$)'; then
	if [[ $audit -eq 1 ]]; then
		devsetup_status install "Rust stable" "would install stable with rustfmt, clippy, rust-src; existing defaults remain unchanged"
		devsetup_status skip "Rust build" "linker readiness is unverified; audit does not compile or run code"
		exit 0
	fi
	devsetup_status install "Rust stable" "installing stable with minimal profile"
	"$rustup" toolchain install stable --profile minimal
fi
if ! printf '%s\n' "$toolchains" | grep -Eq '\([^)]*default[^)]*\)'; then
	if [[ $audit -eq 1 ]]; then
		devsetup_status install "Rust default" "would select stable because no default toolchain exists"
	else
		devsetup_status install "Rust default" "selecting stable because no default toolchain exists"
		"$rustup" default stable
	fi
fi
installed="$("$rustup" component list --installed --toolchain stable)"
for component in rustfmt clippy rust-src; do
	if printf '%s\n' "$installed" | grep -Eq "^$component(-|$)"; then
		devsetup_status found "Rust $component" "installed for stable"
	elif [[ $audit -eq 1 ]]; then
		devsetup_status install "Rust $component" "would add component to stable"
	else
		"$rustup" component add --toolchain stable "$component"
		devsetup_status install "Rust $component" "added to stable"
	fi
done
for tool in rustc cargo; do
	version="$("$rustup" run stable "$tool" --version)"
	devsetup_status found "Rust $tool" "$version"
done
if [[ $check_upgrades -eq 1 ]]; then "$rustup" check; fi
if [[ $audit -eq 1 ]]; then
	devsetup_status skip "Rust build" "linker readiness is unverified; audit does not compile or run code"
	exit 0
fi

rustup_dir="$(dirname "$rustup")"
export PATH="$rustup_dir:$cargo_bin:$PATH"
profile="$HOME/.profile"
if [[ "$(uname -s)" == "Darwin" ]]; then profile="$HOME/.zprofile"; fi
printf -v path_line "export PATH=%q:%q:\"\$PATH\"" "$rustup_dir" "$cargo_bin"
if [[ ! -f "$profile" ]] || ! grep -Fqx "$path_line" "$profile"; then
	if [[ -f "$profile" ]]; then cp "$profile" "$profile.devsetup-backup-$(date -u +%Y%m%d%H%M%S)"; fi
	printf '\n# Added by bos-devsetup-kit for Rust.\n%s\n' "$path_line" >> "$profile"
	devsetup_status install "Rust PATH" "added Rust tools to $profile (new login shells)"
fi
probe="$(mktemp -d)"
trap 'rm -f "$probe/probe.rs" "$probe/probe"; rmdir "$probe"' EXIT
printf '%s\n' 'fn main() { println!("rust-ready"); }' > "$probe/probe.rs"
if "$rustup" run stable rustc --edition 2021 --crate-name devsetup_probe "$probe/probe.rs" -o "$probe/probe" &&
	output="$("$probe/probe")" && [[ "$output" == "rust-ready" ]]; then
	devsetup_status found "Rust build" "stable compiled, linked, and ran a native executable"
else
	devsetup_status warn "Rust build" "toolchain installed but native build/run failed; install the platform C linker/SDK (Xcode Command Line Tools on macOS). No sudo or global linker override was attempted."
fi
