#!/usr/bin/env bash
# Build upstream syntaks (https://github.com/Ciekce/syntaks), unmodified, as a
# standalone TEI executable for each requested target.
#
# Nothing in the syntaks checkout is edited. Two things are overridden at build
# time instead:
#   - upstream's .cargo/config.toml sets `-C target-cpu=native`, which is wrong
#     for a cross build and for a binary that must run on other machines. Cargo
#     prefers target.<triple>.rustflags over build.rustflags, so setting
#     CARGO_TARGET_<TRIPLE>_RUSTFLAGS replaces it without touching the file.
#   - build.rs downloads the NNUE net with curl unless EVALFILE is set. The net
#     is fetched once here, checked against a pinned hash, and passed in.
#
# Usage:  tools/build-syntaks.sh <out-dir> <target>...
#
# Targets and where each lands:
#   host                    <out-dir>/host/syntaks              (x86_64 Linux, for the desktop test)
#   aarch64-linux-android   <out-dir>/arm64-v8a/libsyntaks.so
#   x86_64-linux-android    <out-dir>/x86_64/libsyntaks.so      (emulator test only)
#
# The Android outputs are executables despite the lib*.so name: Android only
# installs files matching lib*.so from the APK's lib/<abi>/ into the app's
# nativeLibraryDir, which is the one app-owned place it still lets an app exec
# from (W^X, targetSdk 29+).
#
# Environment:
#   SYNTAKS_SRC        checkout to build from   (default: <out-dir>/src, cloned at SYNTAKS_REV)
#   EVALFILE           NNUE net to embed        (default: <out-dir>/net/cnet007.nnue, downloaded)
#   ANDROID_NDK        NDK root, for the Android targets
#                      (default: $ANDROID_NDK_LATEST_HOME, $ANDROID_NDK_HOME, $ANDROID_NDK_ROOT)
#   ANDROID_API        minimum API level to link against (default: lowest the NDK offers)

set -euo pipefail

# Pinned upstream commit. Bump deliberately; the net below must match what this
# commit's build.rs names.
SYNTAKS_REV="5e68540c52080ec9b1dacdb3d596c73a40c43b18"
SYNTAKS_URL="https://github.com/Ciekce/syntaks.git"
NET_NAME="cnet007"
NET_SHA256="4d5dc8c03e9d22d0c0a8414e134be9e8da820a50c4814d419e519a3a847afd92"
NET_URL="https://github.com/Ciekce/syntaks-nets/releases/download/$NET_NAME/$NET_NAME.nnue"

die() { echo "error: $*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: $0 <out-dir> <target>..."
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
shift
# Keep Godot from scanning (and importing) the checkout when OUT is inside the project.
touch "$OUT/.gdignore"

SRC="${SYNTAKS_SRC:-$OUT/src}"
if [ ! -d "$SRC/.git" ]; then
	echo "==> fetching syntaks @ $SYNTAKS_REV"
	git init -q "$SRC"
	git -C "$SRC" fetch -q --depth 1 "$SYNTAKS_URL" "$SYNTAKS_REV"
	git -C "$SRC" checkout -q FETCH_HEAD
fi
actual_rev="$(git -C "$SRC" rev-parse HEAD)"
[ "$actual_rev" = "$SYNTAKS_REV" ] || die "$SRC is at $actual_rev, expected $SYNTAKS_REV"
# Refuse to build a checkout with local edits: the point is unmodified upstream.
[ -z "$(git -C "$SRC" status --porcelain --untracked-files=no)" ] || die "$SRC has local modifications"

if [ -z "${EVALFILE:-}" ]; then
	EVALFILE="$OUT/net/$NET_NAME.nnue"
	if [ ! -f "$EVALFILE" ]; then
		echo "==> downloading $NET_NAME"
		mkdir -p "$(dirname "$EVALFILE")"
		curl -fsSL --retry 5 -o "$EVALFILE.part" "$NET_URL"
		mv "$EVALFILE.part" "$EVALFILE"
	fi
fi
echo "$NET_SHA256  $EVALFILE" | sha256sum -c - >/dev/null || die "$EVALFILE does not match the pinned $NET_NAME hash"
export EVALFILE

# Strip symbols: the binary ships in the APK, and nobody symbolicates it there.
export CARGO_PROFILE_RELEASE_STRIP=symbols

ndk_bin() {
	local ndk="${ANDROID_NDK:-${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}}}"
	[ -n "$ndk" ] && [ -d "$ndk" ] || die "Android targets need the NDK; set ANDROID_NDK"
	echo "$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
}

# The NDK names its clang wrappers by API level. Use the requested level, or the
# lowest one shipped, which runs on the most devices.
android_linker() {
	local bin prefix="$1"
	bin="$(ndk_bin)"
	if [ -n "${ANDROID_API:-}" ]; then
		echo "$bin/${prefix}${ANDROID_API}-clang"
	else
		ls "$bin/${prefix}"[0-9]*-clang | sort -V | head -1
	fi
}

for target in "$@"; do
	case "$target" in
	host)
		triple=x86_64-unknown-linux-gnu
		# x86-64-v2 has SSE4.2, so this takes upstream's SSE paths and runs on
		# any CI runner.
		export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C target-cpu=x86-64-v2"
		dest="$OUT/host/syntaks"
		;;
	aarch64-linux-android)
		triple=$target
		linker="$(android_linker aarch64-linux-android)"
		export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$linker"
		# Upstream has no NEON paths; generic aarch64 takes the scalar fallbacks.
		export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="-C target-cpu=generic"
		dest="$OUT/arm64-v8a/libsyntaks.so"
		;;
	x86_64-linux-android)
		triple=$target
		linker="$(android_linker x86_64-linux-android)"
		export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$linker"
		# The Android x86_64 ABI guarantees SSE4.2, which rustc's target spec
		# already enables; x86-64 keeps it at that.
		export CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS="-C target-cpu=x86-64"
		dest="$OUT/x86_64/libsyntaks.so"
		;;
	*)
		die "unknown target '$target'"
		;;
	esac

	echo "==> building syntaks for $triple"
	cargo build --release --locked --manifest-path "$SRC/Cargo.toml" --target "$triple"
	mkdir -p "$(dirname "$dest")"
	cp "$SRC/target/$triple/release/syntaks" "$dest"
	chmod 755 "$dest"

	echo "    $dest"
	file "$dest"
	if [ "$target" != host ]; then
		# An Android executable must be PIE and ask for bionic's linker.
		readelf -d "$dest" | grep -E 'NEEDED|FLAGS'
		readelf -l "$dest" | grep -A1 INTERP | tail -1
		readelf -h "$dest" | grep -q 'DYN' || die "$dest is not position-independent"
	fi
done
