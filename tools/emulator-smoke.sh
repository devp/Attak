#!/usr/bin/env bash
# Install the TEI smoke-test APK on a running emulator (or device), launch it,
# and pass or fail on the result tools/teiGameTest.gd prints to logcat.
#
# The APK comes from the CI-only "Android x86_64 (TEI smoke test)" preset
# (tools/smoke-preset.py), which starts straight into tools/teiGameTest.tscn:
# it finds the bundled engine in nativeLibraryDir and plays a full 6x6 game
# against it through the Vs Bot tab -- the same path the app uses on a phone.
#
# Usage:  tools/emulator-smoke.sh <apk> [timeout-seconds]

set -euo pipefail

APK="$1"
TIMEOUT="${2:-180}"
PKG="gay.cyberwitch.teismoke"
LOG="$(mktemp)"

adb wait-for-device
adb install -r -g "$APK"

# Let a freshly booted emulator settle first. Its post-boot configuration
# changes (overlays and the like) make Android relaunch the foreground activity
# in the same process, which Godot can't survive: the second init crashes.
adb shell am wait-for-broadcast-idle >/dev/null 2>&1 || true
sleep 30

# Stream logcat to a file from before launch. Reading the device buffer back
# afterwards (logcat -d) can miss the result: once the test quits, Godot may be
# re-initialised in the same process and flood the buffer with errors.
adb logcat -c
adb logcat -v time > "$LOG" &
logcat_pid=$!
trap 'kill $logcat_pid 2>/dev/null || true' EXIT

activity="$(adb shell cmd package resolve-activity --brief "$PKG" | tail -1 | tr -d '\r')"
echo "==> launching $activity"
adb shell am start -n "$activity"

result=""
for _ in $(seq 1 "$((TIMEOUT / 3))"); do
	result="$(grep -oE 'TEI_GAME (PASS|FAIL).*' "$LOG" | head -1 || true)"
	[ -n "$result" ] && break
	sleep 3
done
sleep 2

# Everything the app's first process logged (Java tags included: a failed
# startup may only explain itself there), minus the floods: GL shader-limit
# errors from the emulator's software renderer, and the per-function errors a
# second Godot init repeats. Then crash and activity-manager lines.
noise='< info |GLES3|shader|GL_MAX|_compile_specialization|_display_error_with_code|Method/function failed|utility_function|: (1: )?$'
app_pid="$(grep -m1 -oE "Start proc [0-9]+:$PKG/" "$LOG" | grep -oE '[0-9]+' | head -1 || true)"
echo "==> app log, pid ${app_pid:-unknown} ($(wc -l < "$LOG") logcat lines captured)"
if [ -n "$app_pid" ]; then
	grep -E "\(\s*$app_pid\):" "$LOG" | grep -vE "$noise" | awk 'NR <= 250' || true
fi
echo "==> crash, relaunch and configuration-change lines"
grep -E 'F/libc|F/DEBUG.*(signal|Abort|#0[0-4] )|AndroidRuntime|has died|[Rr]elaunch|[Cc]onfig(uration)? ?[Cc]hange|Destroying GodotActivity' "$LOG" \
	| grep -v 'framework.jar' | awk 'NR <= 60' || true

echo "==> ${result:-no TEI_GAME line within ${TIMEOUT}s}"
[[ "$result" == "TEI_GAME PASS"* ]]
