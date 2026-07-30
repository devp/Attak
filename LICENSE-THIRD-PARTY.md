# Third-party components

## Taktician — MIT

Builds that include the `addons/taktician` GDExtension link against
[Taktician](https://github.com/nelhage/taktician), a Tak engine by Nelson Elhage,
licensed **MIT**. The exact commit is pinned in `native/go/go.mod`, and the upstream
licence text is kept verbatim at `native/go/LICENSE-taktician`.

Only Taktician's `ai`, `ptn`, `tak`, `bitboard` and `symmetry` packages are used.
Those depend on nothing outside the Go standard library, so the engine brings no
further third-party code with it.

The glue code — `native/go/engine.go`, `native/build.rs` and `native/src/lib.rs` —
exists only to drive that engine.

### What this means in practice

MIT asks for the copyright notice and licence text to be preserved in
distributions. Ship `native/go/LICENSE-taktician` with any build that bundles the
engine and there is nothing else to do: no copyleft attaches, and bundling it
imposes no licence on Attak's own source.

This is the point of the change. The engine that came before it was
GPL-3.0-or-later, which meant a public release bundling it could not be made at
all while Attak has no licence of its own — that had to be resolved by the project
owner before anything could ship. Under MIT the question does not arise.

### Building without it

The engine is still optional. `LocalBot` (`src/interfaces/localBot.gd`) is the
default opponent, is pure GDScript, and carries no third-party code. To produce a
build with no native engine in it:

```sh
SKIP_TAKTICIAN=1 tools/build-apk.sh
```

The result plays exactly the same, minus the Taktician difficulty options. Nothing
in Attak's own sources depends on the extension — `TakticianBot` reaches the engine
only through `ClassDB`, so the scripts do not even reference it by name.

## godot-rust (`godot` crate) — MPL-2.0

The GDExtension bindings come from [godot-rust](https://github.com/godot-rust/gdext),
licensed MPL-2.0. Used unmodified as a Cargo dependency.

MPL-2.0 is file-level copyleft: it covers the crate's own files, which are not
modified here, and not the code that links against them.

## Other Rust dependencies

`native/Cargo.lock` pins the full transitive set. Beyond godot-rust they are the
usual permissively licensed Rust ecosystem crates.
