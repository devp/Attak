#!/usr/bin/env bash
# Build the AttakEngines Android plugin (android-plugin/) as an AAR carrying the
# bundled engine executables, where the Attak Engines editor plugin hands it to
# Godot's Gradle build.
#
# Usage:  tools/build-plugin.sh <engines-dir>
#
#   <engines-dir>  as written by tools/build-syntaks.sh: <abi>/lib<name>.so for
#                  any of arm64-v8a, x86_64. Every ABI present is packaged; the
#                  app's export preset then picks which ABIs ship.
#
# Output: addons/attak_engines/bin/AttakEngines.aar
#
# Environment:
#   GRADLE        Gradle 8.2+ to run   (default: gradle)
#   ANDROID_HOME  Android SDK root (needs platforms;android-34)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_DIR="$PROJECT_ROOT/android-plugin"
JNI_DIR="$PLUGIN_DIR/src/main/jniLibs"
OUTPUT="$PROJECT_ROOT/addons/attak_engines/bin/AttakEngines.aar"
GRADLE="${GRADLE:-gradle}"

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: $0 <engines-dir>"
ENGINES="$(cd "$1" && pwd)"

rm -rf "$JNI_DIR"
packaged=0
for abi in arm64-v8a x86_64; do
	for so in "$ENGINES/$abi"/lib*.so; do
		[ -f "$so" ] || continue
		mkdir -p "$JNI_DIR/$abi"
		cp "$so" "$JNI_DIR/$abi/"
		echo "==> packaging $abi/$(basename "$so")"
		packaged=$((packaged + 1))
	done
done
[ "$packaged" -gt 0 ] || die "no engines found under $ENGINES/<abi>/lib*.so"

echo "==> building AAR"
"$GRADLE" --no-daemon -p "$PLUGIN_DIR" assembleRelease

mkdir -p "$(dirname "$OUTPUT")"
cp "$PLUGIN_DIR/build/outputs/aar/AttakEngines-release.aar" "$OUTPUT"

echo "==> $OUTPUT"
unzip -l "$OUTPUT" | grep -E 'jni/|classes.jar|AndroidManifest'
for abi in arm64-v8a x86_64; do
	for so in "$JNI_DIR/$abi"/lib*.so; do
		[ -f "$so" ] || continue
		unzip -l "$OUTPUT" | grep -q "jni/$abi/$(basename "$so")" || die "jni/$abi/$(basename "$so") missing from the AAR"
	done
done
