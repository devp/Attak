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

The engine remains optional. `LocalBot` (`src/interfaces/localBot.gd`) is pure
GDScript, is the default opponent, and covers every board size and platform
including the Web export. To build without the extension:

```sh
SKIP_SYNTAKS=1 tools/build-apk.sh
```

Nothing in Attak's own sources depends on it — `SyntaksBot` reaches the engine
only through `ClassDB`, so the scripts do not even name it.

## Note on the previous engine

Earlier revisions of this branch used [tiltak](https://github.com/MortenLohne/tiltak),
which is GPL-3.0-or-later. That imposed real conditions on redistributing Attak,
and since Attak has no licence of its own those conditions could not be satisfied
without a decision from the project owner. Moving to an MIT-licensed engine
removes the question entirely. tiltak is the stronger engine and covers 4x4, 5x5
and 6x6 where syntaks covers only 6x6, so this trades capability for the freedom
to ship.
