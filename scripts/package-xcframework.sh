#!/usr/bin/env bash
# Package the native binary target; Swift modules remain SwiftPM source targets.
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:?Usage: package-xcframework.sh RELEASE_TAG OUTPUT_DIRECTORY}
output=${2:?Usage: package-xcframework.sh RELEASE_TAG OUTPUT_DIRECTORY}
[[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || {
  echo 'Invalid release tag' >&2; exit 1;
}
framework=native/MotionSwiftNative.xcframework
python3 - "$framework" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
with (root / "Info.plist").open("rb") as source:
    libraries = plistlib.load(source)["AvailableLibraries"]
expected = {("macos", ""), ("ios", ""), ("ios", "simulator")}
actual = set()
for library in libraries:
    platform = (library["SupportedPlatform"], library.get("SupportedPlatformVariant", ""))
    if platform not in expected or platform in actual:
        raise SystemExit(f"Unexpected or duplicate platform: {platform}")
    actual.add(platform)
    if library["SupportedArchitectures"] != ["arm64"]:
        raise SystemExit(f"Expected arm64 slice: {library}")
    archive = root / library["LibraryIdentifier"] / library["LibraryPath"]
    if not archive.is_file() or not archive.stat().st_size:
        raise SystemExit(f"Missing or empty archive: {archive}")
    subprocess.run(["lipo", "-verify_arch", "arm64", str(archive)], check=True)
if actual != expected:
    raise SystemExit(f"Missing platforms: {expected - actual}")
PY
mkdir -p "$output"
archive="$output/MotionSwiftNative-$tag.xcframework.zip"
ditto -c -k --sequesterRsrc --keepParent "$framework" "$archive"
checksum=$(swift package compute-checksum "$archive")
[[ "$checksum" =~ ^[a-f0-9]{64}$ ]]
printf '%s  %s\n' "$checksum" "$(basename "$archive")" > "$archive.sha256"
echo "Packaged $archive (SwiftPM checksum: $checksum)"
