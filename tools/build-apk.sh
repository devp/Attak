#!/usr/bin/env bash
# Build an Android APK for Attak, headlessly.
#
# The Android presets use Godot's prebuilt android_debug.apk / android_release.apk
# templates (gradle_build/use_gradle_build=false), so this needs no Gradle, no NDK
# and no Android platform SDK -- only apksigner from build-tools, plus a JDK for
# keytool.
#
# Usage:  tools/build-apk.sh [output.apk]
#
# Environment:
#   GODOT          path to the Godot 4.4.1 editor binary   (default: godot)
#   ANDROID_HOME   Android SDK root                        (default: $ANDROID_SDK_ROOT, then /opt/android-sdk)
#   JAVA_HOME      JDK root                                (default: derived from `java`)
#   PRESET         export preset name                      (default: Android)
#                    "Android"       arm64-v8a + armeabi-v7a, ~56 MB
#                    "Android arm64" arm64-v8a only, ~30 MB
#   RELEASE        set to 1 to export release instead of debug. Release builds are
#                  ~10% smaller, but strip asserts -- prefer debug while testing
#                  game logic, since src/Logic/gameState.gd relies on assertions.
#   SKIP_TAKTICIAN set to 1 to build without the Taktician GDExtension, for when
#                  the Android NDK isn't available to cross-compile it. The result
#                  plays fine, just without the Taktician difficulties.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_VERSION="4.4.1"
GODOT="${GODOT:-godot}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
PRESET="${PRESET:-Android}"
RELEASE="${RELEASE:-0}"
OUTPUT="${1:-$PROJECT_ROOT/build/android/Attak.apk}"

KEYSTORE_DIR="$HOME/.local/share/godot/keystores"

die() { echo "error: $*" >&2; exit 1; }

command -v "$GODOT" >/dev/null || die "Godot not found. Set GODOT to the 4.4.1 editor binary."

actual_version="$("$GODOT" --version | head -1)"
case "$actual_version" in
	"$GODOT_VERSION"*) ;;
	*) echo "warning: expected Godot $GODOT_VERSION, found $actual_version" >&2 ;;
esac

templates_dir="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
template=$([ "$RELEASE" = 1 ] && echo android_release.apk || echo android_debug.apk)
[ -f "$templates_dir/$template" ] || die \
	"missing $templates_dir/$template -- install the export templates for $GODOT_VERSION"

[ -d "$ANDROID_HOME/build-tools" ] || die "no build-tools under $ANDROID_HOME (need apksigner)"

# Resolve exactly one apksigner. An SDK can have several build-tools versions
# installed (GitHub runners ship 34 and 35), so a bare build-tools/*/apksigner
# glob turns the extra matches into arguments and apksigner rejects the command.
APKSIGNER=""
for candidate in $(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | sort -Vr); do
	if [ -x "${candidate}apksigner" ]; then
		APKSIGNER="${candidate}apksigner"
		break
	fi
done
[ -n "$APKSIGNER" ] || die "no apksigner found under $ANDROID_HOME/build-tools"
[ -d "$ANDROID_HOME/platform-tools" ] || die "no platform-tools under $ANDROID_HOME (Godot validates adb is present)"

java_home="${JAVA_HOME:-}"
if [ -z "$java_home" ]; then
	java_home="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
keytool="$java_home/bin/keytool"
[ -x "$keytool" ] || die "no keytool under $java_home/bin"

# Godot reads the SDK and JDK locations from *editor settings*, not from the
# environment, so write them in. (The keystore paths do have env overrides --
# see below -- but these two do not.)
settings="$HOME/.config/godot/editor_settings-4.4.tres"
mkdir -p "$(dirname "$settings")"
if [ ! -f "$settings" ]; then
	printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' > "$settings"
fi
python3 - "$settings" "$ANDROID_HOME" "$java_home" <<'PY'
import re, sys
path, sdk, jdk = sys.argv[1:4]
text = open(path).read()
for key, value in (("export/android/android_sdk_path", sdk),
                   ("export/android/java_sdk_path", jdk)):
    line = f'{key} = "{value}"'
    pattern = re.compile(rf'^{re.escape(key)} = .*$', re.M)
    text = pattern.sub(line, text) if pattern.search(text) else text.rstrip("\n") + "\n" + line + "\n"
open(path, "w").write(text)
PY

mkdir -p "$KEYSTORE_DIR"

if [ "$RELEASE" = 1 ]; then
	# The release preset has no keystore configured (upstream signs by hand), so
	# supply one through Godot's env overrides. Generated on first use; this is a
	# personal sideloading key, not a publishing key.
	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$KEYSTORE_DIR/attak-personal.keystore}"
	export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-attak}"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-attakattak}"
	if [ ! -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ]; then
		echo "==> generating personal release keystore at $GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
		"$keytool" -keyalg RSA -genkeypair \
			-alias "$GODOT_ANDROID_KEYSTORE_RELEASE_USER" \
			-keypass "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" \
			-keystore "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" \
			-storepass "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" \
			-dname "CN=Attak Personal Build, O=Attak, C=US" -validity 10950
	fi
else
	# Godot generates the debug keystore itself on export, but only when its
	# editor settings already name a path. Do it explicitly so a fresh container
	# (or CI image) can't fall through to an unsigned APK.
	export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$KEYSTORE_DIR/debug.keystore}"
	export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
	export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"
	if [ ! -f "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" ]; then
		echo "==> generating debug keystore at $GODOT_ANDROID_KEYSTORE_DEBUG_PATH"
		"$keytool" -keyalg RSA -genkeypair \
			-alias "$GODOT_ANDROID_KEYSTORE_DEBUG_USER" \
			-keypass "$GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD" \
			-keystore "$GODOT_ANDROID_KEYSTORE_DEBUG_PATH" \
			-storepass "$GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD" \
			-dname "CN=Android Debug, O=Android, C=US" -validity 9999
	fi
fi

cd "$PROJECT_ROOT"

# The Taktician GDExtension declares an android.arm64 library. If that .so is
# missing, Godot does NOT fail the export -- it packages a 0-byte file, which then
# fails to dlopen on the device and logs errors on every launch. Refuse to build
# that, and offer an explicit way to opt out instead.
GDEXTENSION="addons/taktician/taktician.gdextension"
ANDROID_LIB="addons/taktician/bin/libattak_taktician.android.arm64.so"

restore_gdextension() {
	if [ -f "$GDEXTENSION.disabled" ]; then
		mv "$GDEXTENSION.disabled" "$GDEXTENSION"
		# Re-import before leaving. The build below runs --import while the
		# extension is moved aside, which deregisters it from .godot/; putting the
		# file back does not undo that, so anything run afterwards would silently
		# not see the engine until the next import.
		"$GODOT" --headless --import >/dev/null 2>&1 || true
	fi
}
trap restore_gdextension EXIT

if [ -f "$GDEXTENSION" ]; then
	if [ "${SKIP_TAKTICIAN:-0}" = 1 ]; then
		echo "==> building without Taktician (SKIP_TAKTICIAN=1)"
		mv "$GDEXTENSION" "$GDEXTENSION.disabled"
	elif [ ! -s "$ANDROID_LIB" ]; then
		# Both toolchains are needed: cargo builds the GDExtension shim, and its
		# build.rs compiles native/go through the NDK's clang. The one linker
		# variable below serves both -- build.rs reads it to find that clang.
		die "$ANDROID_LIB is missing or empty.
  Cross-compile it first (needs Go and the Android NDK):
    rustup target add aarch64-linux-android
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=\$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android34-clang
    cargo build --release --manifest-path native/Cargo.toml --target aarch64-linux-android
    cp native/target/aarch64-linux-android/release/libattak_taktician.so $ANDROID_LIB
  Or build without it:  SKIP_TAKTICIAN=1 $0"
	fi
fi

# Generate .godot/ import caches. The export fails without them, and a fresh
# clone (or CI checkout) has none because .godot/ is gitignored.
echo "==> importing resources"
"$GODOT" --headless --import

# The presets' own export_path points outside the repo (../attak-Build/...), so
# always pass an explicit absolute output path.
mkdir -p "$(dirname "$OUTPUT")"
mode=$([ "$RELEASE" = 1 ] && echo --export-release || echo --export-debug)
echo "==> exporting $OUTPUT  (preset: $PRESET, $mode)"
"$GODOT" --headless "$mode" "$PRESET" "$OUTPUT"

[ -f "$OUTPUT" ] || die "export reported success but produced no APK"

echo "==> verifying with $APKSIGNER"
"$APKSIGNER" verify "$OUTPUT" || die "apksigner could not verify the output"

# Confirm the native engine really landed in the package. Godot only warns when a
# GDExtension library is missing for an architecture, so without this an APK that
# silently lost the engine would still look like a clean build.
if [ -f "$GDEXTENSION" ]; then
	entry=$(unzip -l "$OUTPUT" | awk '/libattak_taktician/ {print $1; exit}')
	if [ -z "$entry" ]; then
		die "the Taktician extension is enabled but no libattak_taktician was packaged into $OUTPUT"
	elif [ "$entry" = "0" ]; then
		die "libattak_taktician was packaged into $OUTPUT as a 0-byte file; it would fail to load on device"
	fi
	echo "    Taktician engine packaged: $entry bytes"
fi

# Godot leaves a v4 signature sidecar behind; it isn't needed to install.
rm -f "$OUTPUT.idsig"

echo
echo "built $(du -h "$OUTPUT" | cut -f1)  $OUTPUT"
unzip -l "$OUTPUT" | grep -E 'lib/[a-z0-9-]+/lib' || true
