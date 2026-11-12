#!/usr/bin/env bash
# Builds the Rust/Skia C ABI and packages it as native/MotionSwiftNative.xcframework, the binary
# target SwiftPM and Xcode link. `--ios` adds iOS device (arm64) and simulator (arm64) slices.
set -euo pipefail
cd "$(dirname "$0")/../.."
export IPHONEOS_DEPLOYMENT_TARGET=17.0 MACOSX_DEPLOYMENT_TARGET=14.0
targets=(aarch64-apple-darwin)
if [ "${1:-}" = "--ios" ]; then targets+=(aarch64-apple-ios aarch64-apple-ios-sim); fi
for target in "${targets[@]}"; do
  rustup target add "$target" >/dev/null
  cargo build --release --locked --manifest-path native/Cargo.toml --target "$target"
done
# Keep the historical host path for tools that link the archive directly.
mkdir -p native/target/release native/pkgconfig
cp native/target/aarch64-apple-darwin/release/libmotionswift_native.a native/target/release/
cat > native/pkgconfig/motionswift-skia.pc <<PC
prefix=$PWD/native
libdir=\${prefix}/target/release

Name: motionswift-skia
Description: MotionSwift's pinned Skia CPU C ABI
Version: 0.1.0
Libs: -L\${libdir} -lmotionswift_native
PC
# Package every slice that exists, so a later macOS-only build keeps previously built iOS slices.
arguments=()
for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
  archive=native/target/$target/release/libmotionswift_native.a
  if [ -f "$archive" ]; then arguments+=(-library "$archive"); fi
done
staging=$(mktemp -d)
xcodebuild -create-xcframework "${arguments[@]}" -output "$staging/MotionSwiftNative.xcframework" >/dev/null
rm -rf native/MotionSwiftNative.xcframework
mv "$staging/MotionSwiftNative.xcframework" native/
rmdir "$staging"
# SwiftPM does not track binary target contents. Invalidate only when an archive changes.
archive_hash=$(cat native/target/*/release/libmotionswift_native.a | shasum -a 256 | cut -d ' ' -f 1)
stamp=native/target/swift-link-checksum
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$archive_hash" ]; then
  swift package clean
  printf '%s\n' "$archive_hash" > "$stamp"
fi
