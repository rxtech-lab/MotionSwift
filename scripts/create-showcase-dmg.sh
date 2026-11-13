#!/usr/bin/env bash
set -euo pipefail
app=${1:?Expected signed app path}
dmg=${2:?Expected output DMG path}
: "${SIGNING_CERTIFICATE_NAME:?Missing Developer ID Application identity}"
[[ -d "$app/Contents" && ! -e "$dmg" ]] || { echo 'Missing app or DMG already exists' >&2; exit 1; }
mkdir -p "$(dirname "$dmg")"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/MotionSwift Showcase.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname 'MotionSwift Showcase' -srcfolder "$stage" -ov -format UDZO "$dmg"
codesign --force --timestamp --sign "$SIGNING_CERTIFICATE_NAME" "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
