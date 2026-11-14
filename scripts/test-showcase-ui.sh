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
session_state=$(swift -e 'import CoreGraphics
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
let locked = session?["CGSSessionScreenIsLocked"] as? Int == 1
let onConsole = session?["kCGSSessionOnConsoleKey"] as? Int == 1
print(session == nil ? "unavailable" : locked ? "locked" : onConsole ? "ready" : "off-console")')
if [[ "$session_state" != ready ]]; then
  printf '{"status":"skipped","reason":"macOS GUI session %s"}\n' "$session_state" > "$report/status.json"
  printf 'SKIP showcase UI tests: macOS GUI session %s; packaged app verification passed.\n' "$session_state"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '### Showcase UI tests: SKIPPED\n\nThe macOS GUI session is %s. The packaged app was built and verified; UI interaction was not exercised.\n' "$session_state" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi
cp tests/ShowcaseUI/project.yml tests/ShowcaseUI/ShowcaseUITests.swift "$stage/"
xcodegen generate --spec "$stage/project.yml" --project "$stage"
cd "$stage"
xcodebuild -project ShowcaseUI.xcodeproj -scheme ShowcaseUI -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$repo/.build/showcase-ui" \
  -resultBundlePath "$report/ShowcaseUI-$(date +%s).xcresult" \
  -parallel-testing-enabled NO "SHOWCASE_UI_APP=$app" test 2>&1 | tee "$report/xcodebuild.log"
