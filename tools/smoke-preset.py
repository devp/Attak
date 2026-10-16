#!/usr/bin/env python3
"""Append a CI-only "Android x86_64 (TEI smoke test)" preset to export_presets.cfg.

It is the "Android" preset, but x86_64 only (for the emulator), installed as a
separate package, and launching straight into tools/teiGameTest.tscn. Generated
in CI rather than committed, so the project's presets stay as they are.

Usage:  tools/smoke-preset.py [export_presets.cfg]
"""
import re
import sys

NAME = "Android x86_64 (TEI smoke test)"
OPTIONS = {
    "architectures/armeabi-v7a": "false",
    "architectures/arm64-v8a": "false",
    "architectures/x86_64": "true",
    "package/unique_name": '"gay.cyberwitch.teismoke"',
    "package/name": '"Attak TEI smoke test"',
    "command_line/extra_args": '"res://tools/teiGameTest.tscn"',
}

path = sys.argv[1] if len(sys.argv) > 1 else "export_presets.cfg"
text = open(path).read()
if f'name="{NAME}"' in text:
    sys.exit(0)

sources = re.finditer(r'(^\[preset\.(\d+)\]\n.*?)(?=^\[preset\.\d+\]\n|\Z)', text, re.M | re.S)
source = next((m for m in sources if re.search(r'^name="Android"$', m.group(1), re.M)), None)
if source is None:
    sys.exit('no "Android" preset to copy')

old = source.group(2)
new = str(max(int(n) for n in re.findall(r'^\[preset\.(\d+)\]$', text, re.M)) + 1)
preset = source.group(1).rstrip("\n") + "\n"
preset = preset.replace(f"[preset.{old}]", f"[preset.{new}]").replace(f"[preset.{old}.options]", f"[preset.{new}.options]")
preset = re.sub(r'^name=.*$', f'name="{NAME}"', preset, count=1, flags=re.M)
preset = re.sub(r'^runnable=.*$', "runnable=false", preset, count=1, flags=re.M)
for key, value in OPTIONS.items():
    preset, n = re.subn(rf'^{re.escape(key)}=.*$', f"{key}={value}", preset, flags=re.M)
    if n != 1:
        sys.exit(f"option {key} not found exactly once in the Android preset")

open(path, "w").write(text.rstrip("\n") + "\n\n" + preset)
print(f"added preset.{new}: {NAME}")
