//! Builds native/go into a c-archive and links it into this crate.
//!
//! Doing it here rather than as a separate step in tools/build-apk.sh means a
//! plain `cargo build` produces a working extension, and that the Go and Rust
//! halves can never drift out of step in a checkout.
//!
//! Cross-compiling for Android needs the NDK's clang as the C compiler for cgo.
//! The CI workflow already exports CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER
//! pointing at exactly that binary, so it is reused rather than asking for the
//! NDK layout a second time in a second variable.

use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    let go_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("go");
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let archive = out_dir.join("libtaktician.a");

    for file in ["engine.go", "go.mod", "go.sum"] {
        println!("cargo:rerun-if-changed={}", go_dir.join(file).display());
    }
    println!("cargo:rerun-if-env-changed=GO");
    println!("cargo:rerun-if-env-changed=CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap();

    let mut go = Command::new(env::var("GO").unwrap_or_else(|_| "go".into()));
    go.current_dir(&go_dir)
        .arg("build")
        .arg("-buildmode=c-archive")
        .arg("-trimpath")
        .arg("-o")
        .arg(&archive)
        .arg(".")
        .env("GOOS", goos(&target_os))
        .env("GOARCH", goarch(&target_arch))
        .env("CGO_ENABLED", "1");

    if target_os == "android" {
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

    let status = go
        .status()
        .unwrap_or_else(|e| panic!("could not run go -- is it installed and on PATH? ({e})"));
    assert!(
        status.success(),
        "go build failed for {target_os}/{target_arch}"
    );

    println!("cargo:rustc-link-search=native={}", out_dir.display());
    println!("cargo:rustc-link-lib=static=taktician");

    // What the Go runtime itself needs from the platform.
    match target_os.as_str() {
        // Bionic folds pthread into libc, but keeps libdl and libm separate, and
        // runtime/cgo logs through liblog on Android.
        "android" => {
            for lib in ["dl", "m", "log"] {
                println!("cargo:rustc-link-lib=dylib={lib}");
            }
        }
        _ => {
            for lib in ["pthread", "dl", "m"] {
                println!("cargo:rustc-link-lib=dylib={lib}");
            }
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
