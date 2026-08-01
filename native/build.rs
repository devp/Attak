//! Builds native/go and links it into this crate.
//!
//! Doing it here rather than as a separate step in tools/build-apk.sh means a
//! plain `cargo build` produces a working extension, and that the Go and Rust
//! halves can never drift out of step in a checkout.
//!
//! The build mode differs by target, and not by choice. Go supports
//! `-buildmode=c-archive` on linux (arm64 included), darwin, ios, aix and
//! windows, but *not* on android -- see `c-archive` in Go's
//! internal/platform/supported.go, which omits it. Android gets `c-shared`
//! instead, which is the mode gomobile uses, and the resulting libtaktician.so
//! ships next to the extension as a GDExtension dependency. So:
//!
//!   desktop  static libtaktician.a linked in; one file to deploy
//!   android  shared libtaktician.so alongside; two files, both landing in the
//!            APK's lib/<abi>/ where the dynamic linker finds them
//!
//! Cross-compiling for Android needs the NDK's clang as the C compiler for cgo.
//! The CI workflow already exports CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
//! pointing at exactly that binary, so it is reused rather than asking for the
//! NDK layout a second time in a second variable.

use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The Android shared library's filename, which is load-bearing in two places at
/// once: the extension records it as its DT_NEEDED at link time, and Godot's
/// save_apk_so packages a dependency under its own basename. Those must agree, so
/// it cannot take the repo's usual `.android.arm64.so` suffix. Godot also refuses
/// any Android library whose name does not start with "lib".
const ANDROID_SO: &str = "libtaktician.so";

fn main() {
    let go_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("go");
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    for file in ["engine.go", "go.mod", "go.sum"] {
        println!("cargo:rerun-if-changed={}", go_dir.join(file).display());
    }
    println!("cargo:rerun-if-env-changed=GO");
    println!("cargo:rerun-if-env-changed=TAKTICIAN_SO_DIR");
    println!("cargo:rerun-if-env-changed=CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let android = target_os == "android";

    // On Android the caller needs to collect the shared library afterwards, and
    // OUT_DIR carries a build hash it cannot predict. TAKTICIAN_SO_DIR lets it say
    // where the file should land instead of globbing for it.
    let so_dir = match env::var("TAKTICIAN_SO_DIR") {
        Ok(dir) if android => {
            let dir = PathBuf::from(dir);
            // A relative path would resolve against the build script's working
            // directory -- the package root, not where cargo was invoked -- which
            // is a trap worth refusing outright rather than documenting.
            assert!(
                dir.is_absolute(),
                "TAKTICIAN_SO_DIR must be an absolute path, got {dir:?}"
            );
            std::fs::create_dir_all(&dir)
                .unwrap_or_else(|e| panic!("could not create TAKTICIAN_SO_DIR {dir:?}: {e}"));
            dir
        }
        _ => out_dir.clone(),
    };

    let output = if android {
        so_dir.join(ANDROID_SO)
    } else {
        out_dir.join("libtaktician.a")
    };

    let mut go = Command::new(env::var("GO").unwrap_or_else(|_| "go".into()));
    go.current_dir(&go_dir)
        .arg("build")
        .arg(if android {
            "-buildmode=c-shared"
        } else {
            "-buildmode=c-archive"
        })
        .arg("-trimpath")
        .arg("-o")
        .arg(&output)
        .env("GOOS", goos(&target_os))
        .env("GOARCH", goarch(&target_arch))
        .env("CGO_ENABLED", "1");

    if android {
        // Pin the soname rather than letting it default to the output path, so
        // what the extension links against is what Godot packages, whatever
        // directory the build wrote to.
        go.arg(format!("-ldflags=-extldflags=-Wl,-soname,{ANDROID_SO}"));

        // cgo needs a compiler that targets the device, not the host. Without
        // this the build silently uses the host cc and fails at link time with
        // architecture mismatches that say nothing about the real cause.
        let cc = android_cc().unwrap_or_else(|| {
            panic!(
                "cross-compiling for Android needs the NDK's clang.\n  \
                 Set CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER (which cargo needs anyway) or \
                 ANDROID_NDK_HOME."
            )
        });
        go.env("CC", &cc);
    }

    go.arg(".");

    let status = go
        .status()
        .unwrap_or_else(|e| panic!("could not run go -- is it installed and on PATH? ({e})"));
    assert!(
        status.success(),
        "go build failed for {target_os}/{target_arch}"
    );

    println!("cargo:rustc-link-search=native={}", so_dir.display());

    if android {
        // Dynamic: the Go runtime lives in libtaktician.so, which carries its own
        // platform links, so there is nothing further for this crate to name.
        println!("cargo:rustc-link-lib=dylib=taktician");
    } else {
        println!("cargo:rustc-link-lib=static=taktician");
        // Statically linked in, so the Go runtime's platform dependencies become
        // this crate's to declare.
        for lib in ["pthread", "dl", "m"] {
            println!("cargo:rustc-link-lib=dylib={lib}");
        }
    }
}

fn goos(target_os: &str) -> &str {
    match target_os {
        "macos" => "darwin",
        other => other, // linux, android and windows already match
    }
}

fn goarch(target_arch: &str) -> &str {
    match target_arch {
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        "x86" => "386",
        "arm" => "arm",
        other => panic!("no Go GOARCH mapping for target architecture {other}"),
    }
}

/// The NDK clang to hand to cgo. Prefers the linker cargo was already told to
/// use, so there is one place to configure the NDK rather than two.
fn android_cc() -> Option<String> {
    if let Ok(linker) = env::var("CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER") {
        if Path::new(&linker).exists() {
            return Some(linker);
        }
    }

    let ndk = [
        "ANDROID_NDK_LATEST_HOME",
        "ANDROID_NDK_HOME",
        "ANDROID_NDK_ROOT",
    ]
    .iter()
    .find_map(|var| env::var(var).ok())?;
    let bin = Path::new(&ndk).join("toolchains/llvm/prebuilt/linux-x86_64/bin");

    // The filename carries the target API level, and which levels ship varies by
    // NDK release. Take the lowest available, which is the most permissive about
    // the devices the result will run on.
    let mut candidates: Vec<_> = std::fs::read_dir(&bin)
        .ok()?
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| name.starts_with("aarch64-linux-android") && name.ends_with("-clang"))
        .collect();
    candidates.sort_by_key(|name| api_level(name));
    candidates
        .first()
        .map(|name| bin.join(name).to_string_lossy().into_owned())
}

fn api_level(clang: &str) -> u32 {
    clang
        .trim_start_matches("aarch64-linux-android")
        .trim_end_matches("-clang")
        .parse()
        .unwrap_or(u32::MAX)
}
