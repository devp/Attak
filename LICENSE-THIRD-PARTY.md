# Third-party components

## tiltak — GPL-3.0-or-later

Builds that include the `addons/tiltak` GDExtension link against
[tiltak](https://github.com/MortenLohne/tiltak), a Tak engine by Morten Lohne,
licensed **GPL-3.0-or-later**. The exact revision is pinned in
`native/Cargo.toml`.

The glue code in `native/src/lib.rs` and `src/interfaces/tiltakBot.gd` exists only
to drive that engine, and is offered under the same terms.

### What this means in practice

GPLv3 obligations attach to **distribution**, not to use. Building this yourself
and installing it on your own device triggers nothing.

If you distribute a build that bundles the tiltak library, then that build is a
combined work covered by the GPLv3, and you must offer its complete corresponding
source — including Attak's own source — under GPLv3-compatible terms.

**Attak has no licence of its own.** Without one, all rights are reserved by the
upstream author, and a GPLv3-compatible combined work cannot be formed. So a
public release bundling tiltak is not something a contributor can decide to
make; it needs a licensing decision from the project owner first.

### Building without it

tiltak is deliberately optional and isolated. `LocalBot`
(`src/interfaces/localBot.gd`) is the default opponent, is pure GDScript, and
carries no third-party code. To produce a build with no GPL code in it at all:

```sh
SKIP_TILTAK=1 tools/build-apk.sh
```

The result plays exactly the same, minus the Tiltak difficulty options. Nothing
in Attak's own sources depends on the extension — `TiltakBot` reaches the engine
only through `ClassDB`, so the scripts do not even reference it by name.

## godot-rust (`godot` crate) — MPL-2.0

The GDExtension bindings come from [godot-rust](https://github.com/godot-rust/gdext),
licensed MPL-2.0. Used unmodified as a Cargo dependency.

## Other Rust dependencies

`native/Cargo.lock` pins the full transitive set. `board-game-traits` and
`pgn-traits` (also by Morten Lohne) are MIT/Apache-2.0; the remainder are the
usual permissively licensed Rust ecosystem crates.
