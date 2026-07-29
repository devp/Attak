#!/usr/bin/env bash
# Build a debug-signed Android APK for Attak, headlessly.
#
# The Android preset uses Godot's prebuilt android_debug.apk template
# (gradle_build/use_gradle_build=false), so this needs no Gradle, no NDK and no
# Android platform SDK -- only apksigner from build-tools, plus a JDK for keytool.
#
# Usage:  tools/build-apk.sh [output.apk]
#
# Honours these environment variables, and otherwise guesses:
#   GODOT          path to the Godot 4.4.1 editor binary   (default: godot)
#   ANDROID_HOME   Android SDK root                        (default: $ANDROID_SDK_ROOT, then /opt/android-sdk)
#   JAVA_HOME      JDK root

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_VERSION="4.4.1"
GODOT="${GODOT:-godot}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
OUTPUT="${1:-$PROJECT_ROOT/build/android/Attak.apk}"

die() { echo "error: $*" >&2; exit 1; }

command -v "$GODOT" >/dev/null || die "Godot not found. Set GODOT to the 4.4.1 editor binary."

actual_version="$("$GODOT" --version | head -1)"
case "$actual_version" in
	"$GODOT_VERSION"*) ;;
	*) echo "warning: expected Godot $GODOT_VERSION, found $actual_version" >&2 ;;
esac

templates_dir="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
[ -f "$templates_dir/android_debug.apk" ] || die \
	"missing $templates_dir/android_debug.apk -- install the export templates for $GODOT_VERSION"

[ -d "$ANDROID_HOME/build-tools" ] || die "no build-tools under $ANDROID_HOME (need apksigner)"
[ -d "$ANDROID_HOME/platform-tools" ] || die "no platform-tools under $ANDROID_HOME (Godot validates adb is present)"

java_home="${JAVA_HOME:-}"
if [ -z "$java_home" ]; then
	java_home="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
[ -x "$java_home/bin/keytool" ] || die "no keytool under $java_home/bin (Godot generates the debug keystore with it)"

# Godot reads the SDK and JDK locations from *editor settings*, not from the
# environment, so write them in. The debug keystore itself does not need to be
# created by hand: Godot's _create_editor_debug_keystore_if_needed() runs keytool
# on first export.
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

cd "$PROJECT_ROOT"

# Generate .godot/ import caches. The export fails without them, and a fresh
# clone (or CI checkout) has none because .godot/ is gitignored.
echo "==> importing resources"
"$GODOT" --headless --import

# The preset's own export_path points outside the repo (../attak-Build/...), so
# always pass an explicit absolute output path.
mkdir -p "$(dirname "$OUTPUT")"
echo "==> exporting $OUTPUT"
"$GODOT" --headless --export-debug "Android" "$OUTPUT"

[ -f "$OUTPUT" ] || die "export reported success but produced no APK"

echo "==> verifying"
"$ANDROID_HOME"/build-tools/*/apksigner verify "$OUTPUT" \
	|| die "apksigner could not verify the output"

echo
echo "built $(du -h "$OUTPUT" | cut -f1)  $OUTPUT"
unzip -l "$OUTPUT" | grep -E 'lib/[a-z0-9-]+/lib' || true
