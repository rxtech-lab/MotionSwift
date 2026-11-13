#!/usr/bin/env bash
# Prerequisite: make compiler native. No certificate is required for a local package check.
set -euo pipefail
cd "$(dirname "$0")/.."
version=${1:-0.0.0}
build=${2:-1}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]] || { echo 'Invalid version' >&2; exit 1; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo 'Invalid build number' >&2; exit 1; }
export PKG_CONFIG_PATH="$PWD/native/pkgconfig:${PKG_CONFIG_PATH:-}"
swift build -c release --product motionswift-showcase
bin=$(swift build -c release --show-bin-path)
mkdir -p .build/showcase
stage=$(mktemp -d "$PWD/.build/showcase/package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
app="$stage/MotionSwift Showcase.app"
resources="$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$resources"
cp "$bin/motionswift-showcase" "$app/Contents/MacOS/"
# These are the only SwiftPM bundles used by the portable showcase.
for name in MotionPortable MotionRuntime motionswift-showcase; do
  ditto "$bin/MotionSwift_$name.bundle" "$resources/MotionSwift_$name.bundle"
done
projects="$resources/ShowcaseProjects"
mkdir -p "$projects/tests/compositions" "$projects/tests/three" \
  "$projects/tests/fixtures/test-film" "$projects/Examples/MotionStudio"
ditto tests/compositions/src "$projects/tests/compositions/src"
ditto tests/compositions/visuals "$projects/tests/compositions/visuals"
ditto tests/three/src "$projects/tests/three/src"
ditto tests/maps "$projects/tests/maps"
ditto tests/three/public "$projects/tests/three/public"
ditto Examples/MotionStudio/SampleProject "$projects/Examples/MotionStudio/SampleProject"
cp tests/fixtures/test-film/project.zip tests/fixtures/test-film/project.zip.sha256 \
  "$projects/tests/fixtures/test-film/"
cp LICENSE "$resources/MotionSwift-LICENSE.txt"
xcrun actool Examples/AppIcon.icon --compile "$resources" --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$stage/icon-info.plist" --output-format human-readable-text
python3 - "$app" "$version" "$build" "$stage/icon-info.plist" <<'PY'
from pathlib import Path
import plistlib, sys
app, version, build, icon = sys.argv[1:]
info = dict(CFBundleIdentifier='app.rxlab.MotionSwift.Showcase', CFBundleName='MotionSwift Showcase',
            CFBundleDisplayName='MotionSwift Showcase', CFBundleExecutable='motionswift-showcase',
            CFBundlePackageType='APPL', CFBundleShortVersionString=version, CFBundleVersion=build,
            LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
            NSPrincipalClass='NSApplication')
info.update(plistlib.loads(Path(icon).read_bytes()))
(Path(app) / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
python3 scripts/bundle-showcase-tools.py "$app" "${FFMPEG_PATH:-$(command -v ffmpeg)}"
# Make local packages launchable after rewriting dylib load commands. Release signing replaces this.
while IFS= read -r -d '' binary; do
  codesign --force --sign - "$binary"
done < <(find "$app/Contents/Frameworks" "$app/Contents/Helpers" -type f -print0)
codesign --force --sign - --entitlements Examples/Showcase.entitlements "$app"
codesign --verify --deep --strict "$app"
# A unique output avoids destroying a previous local package.
destination="$PWD/.build/showcase/MotionSwift-Showcase-$version-$build.app"
[[ ! -e "$destination" ]] || { echo "Output exists: $destination" >&2; exit 1; }
mv "$app" "$destination"
printf '%s\n' "$destination"
