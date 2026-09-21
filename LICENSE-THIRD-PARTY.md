# Third-party components

## syntaks — MIT

The `addons/syntaks` GDExtension links against
[syntaks](https://github.com/Ciekce/syntaks), a TEI Tak engine by Ciekce,
licensed **MIT**.

MIT asks only that the copyright notice and permission notice travel with the
software. It places **no conditions on how Attak itself is licensed or
distributed**, so bundling the engine in a public release is unproblematic.

### Why this depends on a fork

`native/Cargo.toml` points at [devp/syntaks](https://github.com/devp/syntaks),
branch `portable-road-and-lib-target`, pinned to an exact revision. Upstream
cannot be embedded as it stands, for three reasons:

1. **It does not run on ARM.** `has_road` — road detection, and so the primary
   win condition — dispatched to AVX2 or SSE4.2 and fell through to `todo!()` on
   anything else, which panics. That covers all of aarch64. The fork adds a
   portable implementation and pins it to the SIMD ones with a differential test.
2. **It could not be linked.** syntaks was a binary-only crate with every module
   private, usable only as a subprocess over TEI — which is exactly what Android
   forbids. The fork adds a library target.
3. **The result could only be printed.** The search reported its move by writing
   `bestmove` to stdout, with nothing recording it. An embedding host has no pipe
   to read. The fork stores the move and adds an accessor.

All three are small, upstreamable changes that leave the engine's behaviour as a
binary untouched. If they land upstream, the dependency can point back at
`Ciekce/syntaks` with no other change.

## godot-rust (`godot` crate) — MPL-2.0

The GDExtension bindings come from [godot-rust](https://github.com/godot-rust/gdext),
licensed MPL-2.0. Used unmodified as a Cargo dependency.

## Other Rust dependencies

`native/Cargo.lock` pins the full transitive set — permissively licensed Rust
ecosystem crates throughout.

## Building without the engine

The engine remains optional: without it the Vs Bot tab is hidden and the rest of
Attak is unaffected. To build without the extension:

```sh
SKIP_SYNTAKS=1 tools/build-apk.sh
```

Nothing in Attak's own sources depends on it — `SyntaksBot` reaches the engine
only through `ClassDB`, so the scripts do not even name it.
