#!/usr/bin/env bash
# Install the TEI smoke-test APK on a running emulator (or device), launch it,
# and pass or fail on the result tools/teiSmokeTest.gd prints to logcat.
#
# The APK comes from the "Android x86_64 (TEI smoke test)" preset, which starts
# straight into tools/teiSmokeTest.tscn: it finds the bundled engine through the
# AttakEngines plugin, spawns it with OS.execute_with_pipe, and checks for
# teiok / readyok / bestmove -- the same path the app uses on a phone.
#
# Usage:  tools/emulator-smoke.sh <apk> [timeout-seconds]

set -euo pipefail

APK="$1"
TIMEOUT="${2:-180}"
PKG="gay.cyberwitch.teismoke"

adb wait-for-device
adb install -r -g "$APK"
adb logcat -c

activity="$(adb shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')"
echo "==> launching $activity"
adb shell am start -n "$activity"

result=""
for _ in $(seq 1 "$((TIMEOUT / 3))"); do
	result="$(adb logcat -d -s godot:V | grep -oE 'TEI_SMOKE (PASS|FAIL.*)' | head -1 || true)"
	[ -n "$result" ] && break
	sleep 3
done

echo "==> godot log"
adb logcat -d -s godot:V | grep -v '< info' | tail -60
# Where Android put the engine, and with what permissions -- useful if the
# spawn failed. run-as works because the smoke APK is a debug build.
echo "==> nativeLibraryDir"
adb shell pm dump "$PKG" | grep -m1 -E 'legacyNativeLibraryDir|nativeLibraryDir' || true
libdir="$(adb shell pm dump "$PKG" | grep -m1 -oE 'nativeLibraryDir=\S+' | cut -d= -f2 | tr -d '\r' || true)"
[ -n "$libdir" ] && adb shell ls -lZ "$libdir" || true

echo "==> ${result:-no TEI_SMOKE line within ${TIMEOUT}s}"
[[ "$result" == "TEI_SMOKE PASS" ]]
