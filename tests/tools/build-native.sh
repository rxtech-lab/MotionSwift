#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
cargo build --release --locked --manifest-path native/Cargo.toml
mkdir -p native/pkgconfig
cat > native/pkgconfig/motionswift-skia.pc <<PC
prefix=$PWD/native
libdir=\${prefix}/target/release

Name: motionswift-skia
Description: MotionSwift's pinned Skia CPU C ABI
Version: 0.1.0
Libs: -L\${libdir} -lmotionswift_native
PC
# SwiftPM does not track static libraries outside its source graph. Invalidate only when the archive changes.
archive_hash=$(shasum -a 256 native/target/release/libmotionswift_native.a | cut -d ' ' -f 1)
stamp=native/target/swift-link-checksum
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$archive_hash" ]; then
  swift package clean
  printf '%s\n' "$archive_hash" > "$stamp"
fi
