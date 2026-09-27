godot := env("GODOT", "godot")
syntaks_macos := "addons/syntaks/bin/libattak_syntaks.macos.dylib"

# Export the standalone macOS app (universal, ad-hoc signed)
macos out="build/macos/Attak.app": syntaks-macos
    mkdir -p "$(dirname '{{out}}')"
    {{godot}} --headless --import
    {{godot}} --headless --export-release macOS '{{out}}'

# Build the syntaks GDExtension as a universal macOS dylib
syntaks-macos:
    rustup target add x86_64-apple-darwin aarch64-apple-darwin
    cargo build --release --manifest-path native/Cargo.toml --target x86_64-apple-darwin
    cargo build --release --manifest-path native/Cargo.toml --target aarch64-apple-darwin
    mkdir -p "$(dirname {{syntaks_macos}})"
    lipo -create -output {{syntaks_macos}} \
        native/target/x86_64-apple-darwin/release/libattak_syntaks.dylib \
        native/target/aarch64-apple-darwin/release/libattak_syntaks.dylib
