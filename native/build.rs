use std::{env, fs, path::PathBuf};

fn main() {
    println!("cargo:rerun-if-changed=src/svg.cpp");
    println!("cargo:rerun-if-env-changed=SKIA_SOURCE_DIR");
    let headers = env::var_os("SKIA_SOURCE_DIR").map(PathBuf::from).or_else(|| {
        let cargo_home = env::var_os("CARGO_HOME").map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").expect("HOME is required")).join(".cargo"));
        fs::read_dir(cargo_home.join("registry/src")).ok()?.filter_map(Result::ok)
            .map(|entry| entry.path().join("skia-bindings-0.99.0/skia"))
            .find(|path| path.join("include/core/SkCanvas.h").is_file())
    }).expect("Pinned skia-bindings 0.99.0 headers are required; set SKIA_SOURCE_DIR for a custom Cargo source");
    cc::Build::new()
        .cpp(true)
        .std("c++17")
        .flag("-fno-rtti")
        .flag_if_supported("-Wno-unused-parameter")
        .define("NDEBUG", None)
        .include(headers)
        .file("src/svg.cpp")
        .compile("motionswift-svg");
}
