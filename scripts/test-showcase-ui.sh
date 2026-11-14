#!/usr/bin/env bash
# Requires an unlocked macOS GUI session and Xcode UI automation permission for the runner.
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$PWD"
report="$repo/tests/reports/showcase-ui"
mkdir -p "$report"
stage=$(mktemp -d "${TMPDIR:-/tmp}/motionswift-showcase-ui.XXXXXX")
trap 'rm -rf "$stage"' EXIT
# Test the same release payload shipped to users, with no checkout-relative asset resolution.
bash scripts/package-showcase.sh 0.0.0 "$(date +%s)" | tee "$report/package.log"
packaged=$(tail -n 1 "$report/package.log")
app="$stage/MotionSwift Showcase.app"
ditto "$packaged" "$app"
python3 scripts/verify-showcase-package.py "$app"
cp tests/ShowcaseUI/project.yml tests/ShowcaseUI/ShowcaseUITests.swift "$stage/"
xcodegen generate --spec "$stage/project.yml" --project "$stage"
cd "$stage"
xcodebuild -project ShowcaseUI.xcodeproj -scheme ShowcaseUI -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$repo/.build/showcase-ui" \
  -resultBundlePath "$report/ShowcaseUI-$(date +%s).xcresult" \
  -parallel-testing-enabled NO "SHOWCASE_UI_APP=$app" test 2>&1 | tee "$report/xcodebuild.log"
