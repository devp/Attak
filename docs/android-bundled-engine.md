# Bundled engine on Android (Vs Bot tab)

How Attak ships a TEI engine inside its Android app, and the evidence behind it.

## How it works

1. **Engine.** `tools/build-syntaks.sh` builds upstream [syntaks](https://github.com/Ciekce/syntaks)
   at a pinned commit (`5e68540`), unmodified, as a plain executable. Two build-time
   overrides only: `CARGO_TARGET_<TRIPLE>_RUSTFLAGS` replaces upstream's
   `target-cpu=native`, and `EVALFILE` supplies the hash-checked `cnet007` net. The
   minimum Rust is 1.97.0: 1.94 lacks `cfg_select!`, and 1.95–1.96 lack
   `u64::isolate_lowest_one`.
2. **Packaging.** `addons/attak_engines` is an editor export plugin. For each ABI the
   preset ships, it `add_shared_object`s `addons/attak_engines/bin/<abi>/lib*.so`, which
   Godot places at `lib/<abi>/` in the APK. Godot's prebuilt APK template uses legacy
   packaging (`extractNativeLibs=true`, libs deflated), so Android extracts them to the
   app's `nativeLibraryDir` with exec permission. That's the one app-owned place Android
   still lets an app run its own executables from (W^X since targetSdk 29). No Gradle
   build, no Java.
3. **Finding it.** `BundledEngines.gd` reads `nativeLibraryDir` off where
   `libgodot_android.so` is mapped (`/proc/<pid>/maps`, via `grep`), and checks files
   with `ls`. Godot's own Android `FileAccess` can't see `/data/app/...`: its Java handler
   only knows app, asset and shared storage, and reports anything else as missing.
4. **Playing.** The Vs Bot tab (`BotMenu.gd`) lists bundled engines, offers only the
   sizes and komi in the engine's manifest entry (syntaks: 6x6, komi 2), and starts the
   game through the existing, unchanged `TEInterface` (`OS.execute_with_pipe`).

## Evidence

- **ARM correctness.** syntaks falls back to scalar code without AVX2/SSE (`road.rs`,
  `eval/nnue.rs`, `hits.rs`), and there's no `todo!()` anywhere. `syntaks bench` gives
  8,854,888 nodes for the AVX2, scalar x86 and aarch64 (qemu) builds alike, so the
  scalar search is bit-identical.
- **Phone (arm64), first spike, 2026-10-16.** The engine was extracted as
  `-rwxr-xr-x … libsyntaks.so` in `nativeLibraryDir`. The `/proc/maps` directory matched
  the one Android reports. Handshake OK; 5 s search: depth 16, **1.56M nps**. A full
  6x6 game played to the end. That spike used a Gradle-built plugin to find
  `nativeLibraryDir`; the current build reads the same directory from `/proc/maps`,
  which the phone showed to agree.
- **Phone (arm64), current build, 2026-10-16.** The no-Gradle `Attak.apk` showed the
  Vs Bot tab and played a game against bundled syntaks.
- **CI.** `tools/teiGameTest` plays a full 6x6 game through the real Vs Bot tab
  (`TEInterface` drives syntaks as Black, a second syntaks stands in for the human), on
  desktop and on an API 34 x86_64 emulator. `tools/build-apk.sh` fails the build if the
  engine is missing from the APK or `extractNativeLibs` is false.

## Gotchas

- `OS.execute_with_pipe` on Android is the plain `OS_Unix` fork/exec. A refused exec
  shows up as `Could not create child process` on the engine's stderr and exit code 9.
- An idle `TEInterface` has `pid` 0, and on exit `OS.is_process_running(0)` /
  `OS.kill(0)` act on the whole process group. With a second `TEInterface` running an
  engine, that SIGKILLs the app (and on desktop, its launching shell). So the Vs Bot tab
  shares the TEI tab's `TEI` node instead of adding its own.
- syntaks plays 6x6 with komi 2 only. Anything else just prints to stderr and it carries
  on with 6x6 / komi 2, hence the manifest-driven size and komi.
- When the bot plays White, `TEInterface` sends `position tps startpos`. syntaks rejects
  it but is already at startpos, so play is correct.
- Strength: one engine process per game on a real clock ("Bot Time") plays far stronger
  than the old GDExtension tab's 40k nodes per move. An easy level would mean
  `TEInterface` sending `go nodes N`.
