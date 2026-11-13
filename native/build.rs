use std::{env, fs, path::PathBuf, process::Command};

// The source revision used by skia-bindings 0.99.0 (its m150-0.98.1 tag).
const SKIA_REVISION: &str = "90af6f5c5a3ed8788b805fe6ca3fcdf28c2c2bc9";
const SKIA_ARCHIVE_SHA256: &str =
    "43bb259a802f99f3bf1f68757180bac1cff825107f13870a6ec416f6ad2e2690";

fn headers() -> PathBuf {
    if let Some(path) = env::var_os("SKIA_SOURCE_DIR") {
        return path.into();
    }
    let cargo_home = env::var_os("CARGO_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required")).join(".cargo")
        });
    if let Ok(registries) = fs::read_dir(cargo_home.join("registry/src")) {
        if let Some(path) = registries
            .filter_map(Result::ok)
            .map(|entry| entry.path().join("skia-bindings-0.99.0/skia"))
            .find(|path| path.join("include/core/SkCanvas.h").is_file())
        {
            return path;
        }
    }
    // Prebuilt Skia packages omit headers. Obtain the matching header trees,
    // independently of whether skia-bindings chose a binary download or a source build.
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is required"));
    let directory = format!("skia-{SKIA_REVISION}");
    let path = output.join(&directory);
    let stamp = path.join(".verified");
    if !stamp.is_file() || !path.join("modules/skcms/skcms.h").is_file() {
        let archive = output.join("skia-headers.tar.gz");
        let status = Command::new("curl")
            .args([
                "--fail",
                "--location",
                "--retry",
                "2",
                "--silent",
                "--show-error",
            ])
            .arg(format!(
                "https://codeload.github.com/rust-skia/skia/tar.gz/{SKIA_REVISION}"
            ))
            .arg("--output")
            .arg(&archive)
            .status()
            .expect("curl is required to download Skia headers");
        assert!(
            status.success(),
            "Skia header download failed; set SKIA_SOURCE_DIR for offline builds"
        );
        let digest = Command::new("shasum")
            .args(["-a", "256"])
            .arg(&archive)
            .output()
            .expect("shasum is required");
        assert!(
            digest.status.success()
                && String::from_utf8_lossy(&digest.stdout)
                    .split_whitespace()
                    .next()
                    == Some(SKIA_ARCHIVE_SHA256),
            "Skia source archive checksum mismatch"
        );
        let status = Command::new("tar")
            .arg("-xzf")
            .arg(&archive)
            .arg("-C")
            .arg(&output)
            .args([
                format!("{directory}/include"),
                format!("{directory}/src"),
                format!("{directory}/modules/skcms"),
                format!("{directory}/LICENSE"),
            ])
            .status()
            .expect("tar is required to extract Skia headers");
        assert!(status.success(), "Skia header extraction failed");
        fs::write(&stamp, SKIA_ARCHIVE_SHA256).expect("Cannot record verified Skia headers");
        fs::remove_file(archive).expect("Cannot remove Skia source archive");
    }
    path
}

fn main() {
    println!("cargo:rerun-if-changed=src/svg.cpp");
    println!("cargo:rerun-if-env-changed=SKIA_SOURCE_DIR");
    cc::Build::new()
        .cpp(true)
        .std("c++20")
        .flag("-fno-rtti")
        .flag_if_supported("-Wno-unused-parameter")
        .define("NDEBUG", None)
        .include(headers())
        .file("src/svg.cpp")
        .compile("motionswift-svg");
}
