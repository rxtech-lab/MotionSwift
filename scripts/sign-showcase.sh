#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:?Expected app path}
: "${SIGNING_CERTIFICATE_NAME:?Missing Developer ID Application identity}"
[[ "$SIGNING_CERTIFICATE_NAME" == 'Developer ID Application:'* ]] || {
  echo 'Distribution requires a Developer ID Application certificate' >&2; exit 1;
}
while IFS= read -r -d '' binary; do
  codesign --force --options runtime --timestamp --sign "$SIGNING_CERTIFICATE_NAME" "$binary"
done < <(find "$app/Contents/Frameworks" "$app/Contents/Helpers" -type f -print0)
codesign --force --options runtime --timestamp --entitlements Examples/Showcase.entitlements \
  --sign "$SIGNING_CERTIFICATE_NAME" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
