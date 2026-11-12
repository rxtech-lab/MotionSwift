#!/usr/bin/env bash
# Builds the MotionStudio example app for the iOS Simulator and for iOS devices (unsigned), and
# optionally runs its XCUITests on a simulator: `tests/tools/build-ios.sh --test`.
# Requires `make compiler native-ios` (portable JS resources and iOS Skia slices).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
project="$repo/Examples/MotionStudio/MotionStudio.xcodeproj"
derived="${MOTIONSWIFT_DERIVED_DATA:-$repo/.build/ios}"
if command -v xcodegen >/dev/null; then
  xcodegen generate --quiet --spec "$repo/Examples/MotionStudio/project.yml" --project "$repo/Examples/MotionStudio"
fi
common=(-project "$project" -scheme MotionStudio -derivedDataPath "$derived")
xcodebuild "${common[@]}" -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild "${common[@]}" -configuration Debug -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild "${common[@]}" -configuration Release -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO -quiet
echo "MotionStudio builds: iOS Simulator (Debug), iOS device (Debug, Release)"
if [ "${1:-}" = "--test" ]; then
  simulator="${MOTIONSWIFT_SIMULATOR:-iPad Pro 13-inch (M5)}"
  xcodebuild "${common[@]}" -configuration Debug -destination "platform=iOS Simulator,name=$simulator" \
    -resultBundlePath "$derived/EditorUITests-$(date +%s).xcresult" test
fi
