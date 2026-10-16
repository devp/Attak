# Android TEI via bundled syntaks: Phase 0 findings

Status: 1–5 all confirmed in CI, including on an Android x86_64 emulator (API 34).
Still to do: a real arm64 phone (the diagnostics screen).

## Emulator evidence (CI run 38927719389, job `emulator`)

The x86_64 smoke-test APK, launched on the API 34 emulator, logged:

    bundled engine directory: '/data/app/~~gtWUsGZ…==/gay.cyberwitch.teismoke-cASZ…==/lib/x86_64'
    -rwxr-xr-x 1 system system  6266672 1981-01-01 01:01 libsyntaks.so
    can_execute: 1
    # spawning /data/app/…/lib/x86_64/libsyntaks.so
    # pid 3454
    > tei   < id name syntaks 0.1.0 … < teiok   > isready   < readyok
    > go movetime 1000   < bestmove a6        (nps 317347, emulated)
    TEI_SMOKE PASS

So on Android: the plugin returns `nativeLibraryDir` (item 5), the libs are extracted
there with mode 0755 (item 4), and `OS.execute_with_pipe` spawns the engine from it and
talks TEI (item 3).

## 1. Upstream syntaks runs on ARM unmodified: yes

At HEAD `5e68540` (still HEAD on 2026-10-16):

- `src/road.rs` and `src/eval/nnue.rs` use `cfg_select!` with a `_ =>` arm that falls
  back to `scalar` when AVX2/SSE4.x aren't enabled.
- `src/hits.rs` uses `pext` only with `all(feature = "pext", target_feature = "bmi2")`,
  and `magic` otherwise. `src/hits/common.rs` imports `_pdep_u64` only under `bmi2`,
  with a portable loop otherwise.
- `src/ttable.rs` prefetch has explicit `x86_64` and `aarch64` (`prfm`) arms, plus a
  no-op `_` arm.
- No `todo!()` or `unimplemented!()` anywhere in `src/`.

Evidence (built in this session, no source changes):

| build | `syntaks bench` nodes | nps |
|---|---|---|
| x86_64, `target-cpu=x86-64-v3` (AVX2 paths) | 8,854,888 | 1.09M |
| x86_64, `target-cpu=x86-64` (scalar paths) | 8,854,888 | 0.86M |
| aarch64-unknown-linux-musl, under qemu-aarch64 | 8,854,888 | 0.09M (emulated) |

The node counts are identical, so the scalar paths search exactly the same as the SIMD
ones. The aarch64 binary also completed `tei`/`isready`/`go movetime` under qemu.
`cargo check --target aarch64-linux-android` passes.

## 2. syntaks builds as an Android executable: yes

- `target-cpu=native` comes from upstream `.cargo/config.toml` `[build] rustflags`.
  Cargo prefers `target.<triple>.rustflags`, so `CARGO_TARGET_<TRIPLE>_RUSTFLAGS`
  replaces it without editing upstream. Confirmed: the baseline and v3 builds above
  differ in speed as expected.
- NNUE net: `build.rs` honours `EVALFILE`. `tools/build-syntaks.sh` downloads
  `cnet007.nnue` once, checks sha256 `4d5dc8c0…afd92`, and passes it in. CI caches it.
- **Minimum Rust: 1.97.0.** 1.94 fails (`cfg_select` unstable). 1.95 and 1.96 fail
  (`isolate_most_least_significant_one` unstable, used for `isolate_lowest_one`).
  1.97.0 builds. Pinned in CI as `RUST_TOOLCHAIN`.
- Pinned to `5e68540c52080ec9b1dacdb3d596c73a40c43b18`. The script refuses a checkout
  at another commit or with local edits.
- The `file`/`readelf -d` output for both Android builds is in the `apk` job log
  ("Build syntaks"). The APKs carry `lib/arm64-v8a/libsyntaks.so` and
  `lib/x86_64/libsyntaks.so` (about 6.2 MB each, deflated, so legacy packaging is in
  effect), and the manifest says `extractNativeLibs=true`.

## 3. `OS.execute_with_pipe` on Android (Godot 4.4.1): yes (emulator)

`OS_Android` overrides only `execute` and `create_process`, and only for its own
`ANDROID_EXEC_PATH`. `execute_with_pipe` is the generic `OS_Unix` implementation:
`pipe()` ×3, `fork()`, `dup2`, `execvp`. If `execvp` fails, the child prints
`Could not create child process: <path>` to the stderr pipe and `SIGKILL`s itself.
Reproduced on desktop with a non-executable file. The diagnostics screen shows exactly
that line and "exit code 9" if Android refuses the exec.

## 4. Bundling an executable Android will exec: yes, via the v2 plugin (emulator)

- v2 plugin AAR (`android-plugin/`) with `jniLibs/<abi>/libsyntaks.so`, registered via
  `org.godotengine.plugin.v2.AttakEngines`. Handed to Gradle by an editor export plugin
  (`addons/attak_engines`, `_get_android_libraries`). Godot 4.4.1 passes those as
  `plugins_local_binaries` and the template adds `implementation files(...)`.
- **Extraction:** in Godot 4.4.1's template, `gradle_build/compress_native_libraries`
  maps directly to `jniLibs.useLegacyPackaging` (`config.gradle`
  `shouldUseLegacyPackaging`). With minSdk < 23 it's forced true anyway. The new presets
  set it true. `build-apk.sh` fails if the APK says `extractNativeLibs=false`, and logs
  the lib's size and storage method.
- Template: installed headlessly with `--install-android-build-template` (4.4.1 CLI flag),
  after `rm -rf android/`, so every build uses a pristine template that is never edited.
- Godot 4.4.1's template pins `ndkVersion 23.2.8568313`. The runner doesn't have it,
  and the Gradle build succeeds anyway.
- Gotcha found in CI: Godot 4.4.1 refuses *non-Gradle* Android exports while any export
  plugin supports Android ("Use Gradle Build" must be enabled to use the plugins), and
  it asks without naming the preset. The export plugin therefore claims Android only
  when its AAR exists, and `build-apk.sh` sets `ATTAK_SKIP_ENGINE_PLUGIN=1` for
  non-Gradle presets, so the universal APK still builds.

## 5. Finding nativeLibraryDir from GDScript: plugin method (emulator)

Gotcha found in CI: Godot's `FileAccess.file_exists` returns false for files in
`nativeLibraryDir`. Its Android `FileAccessHandler` only knows app, assets and shared
storage, and classifies `/data/app/...` as `StorageScope.UNKNOWN`. So the plugin also
provides `fileExists(path)`, and `BundledEngines.exists()` uses it.


`Engine.get_singleton("AttakEngines").getNativeLibraryDir()` returns
`getActivity().getApplicationInfo().nativeLibraryDir`. Also `canExecute(path)`, because
Godot's Android `FileAccess` returns 0 for `get_unix_permissions` on absolute paths
(`file_access_filesystem_jandroid.h`). The diagnostics screen cross-checks the directory
against the one `libgodot_android.so` is mapped from (`/proc/<pid>/maps`). It also
notes that 4.4.1 ships an `AndroidRuntime` singleton, a JNI-free fallback if ever needed.

## Notes for Phase 1

- syntaks supports 6x6 only, with komi fixed at 2 (`HalfKomi` min = max = 4). Other
  sizes or komi produce only a stderr message (`Only 6x6 supported`,
  `Unsupported komi value`), and the engine keeps playing 6x6 / komi 2.
  **Decision (Dev):** keep it simple. Before starting, if the chosen engine is bundled
  syntaks and the game isn't 6x6 with komi 2, show an error and don't start. The limits
  live in the bundled-engine manifest entry, not in a name check.
- When the bot plays white, `TEInterface` sends `position tps startpos`. syntaks rejects
  it (`Failed to parse TPS`) but is already at startpos after `teinewgame`, so play is
  correct. Harmless, though only by accident.
- The spike APK uses package `gay.cyberwitch.tei` ("Attak TEI"), so it installs
  alongside any earlier `gay.cyberwitch` build signed with a different key.
