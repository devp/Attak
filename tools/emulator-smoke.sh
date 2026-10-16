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
LOG="$(mktemp)"

adb wait-for-device
adb install -r -g "$APK"

# Stream logcat to a file from before launch. Reading the device buffer back
# afterwards (logcat -d) can miss the result: once the test quits, Godot may be
# re-initialised in the same process and flood the buffer with errors.
adb logcat -c
adb logcat -v time -s godot:V AndroidRuntime:V DEBUG:V libc:V ActivityManager:I > "$LOG" &
logcat_pid=$!
trap 'kill $logcat_pid 2>/dev/null || true' EXIT

activity="$(adb shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')"
echo "==> launching $activity"
adb shell am start -n "$activity"

result=""
for _ in $(seq 1 "$((TIMEOUT / 3))"); do
	result="$(grep -oE 'TEI_SMOKE (PASS|FAIL.*)' "$LOG" | head -1 || true)"
	[ -n "$result" ] && break
	sleep 3
done
sleep 2

echo "==> log ($(wc -l < "$LOG") lines; engine search 'info' lines and repeated GL/re-init errors omitted)"
grep -vE '< info |GLES3|shader|GL_MAX|_compile_specialization|_display_error_with_code|Method/function failed|utility_function|godot   : (1: )?$|already exist|singleton != nullptr|not supported\.$|\(core/' "$LOG" | head -200

echo "==> ${result:-no TEI_SMOKE line within ${TIMEOUT}s}"
[[ "$result" == "TEI_SMOKE PASS" ]]
