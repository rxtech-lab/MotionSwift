#!/usr/bin/env bash
# Signs inside-out, notarizes/staples the app, then signs/notarizes/staples the DMG.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_CERTIFICATE_NAME:?Missing Developer ID Application identity}"
: "${APPLE_ID:?Missing notarization Apple ID}"
: "${APPLE_ID_PWD:?Missing app-specific password}"
: "${APPLE_TEAM_ID:?Missing Apple team ID}"
app=${1:?Expected app path}
dmg=${2:?Expected DMG path}
[[ -d "$app/Contents" && ! -e "$dmg" ]] || { echo 'Missing app or DMG already exists' >&2; exit 1; }
mkdir -p "$(dirname "$dmg")"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
notary() {
  local artifact=$1 label=$2 result="$work/$2.json"
  if ! xcrun notarytool submit "$artifact" --apple-id "$APPLE_ID" --password "$APPLE_ID_PWD" \
    --team-id "$APPLE_TEAM_ID" --wait --timeout 30m --output-format json > "$result"; then
    cat "$result"
    return 1
  fi
  if ! python3 - "$result" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print('Notarization:', result.get('id'), result.get('status'))
sys.exit(0 if result.get('status') == 'Accepted' else 1)
PY
  then
    id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$result")
    xcrun notarytool log "$id" --apple-id "$APPLE_ID" --password "$APPLE_ID_PWD" \
      --team-id "$APPLE_TEAM_ID" "$(dirname "$dmg")/$label-notary-log.json"
    return 1
  fi
  cp "$result" "$(dirname "$dmg")/$label-notary-result.json"
}
bash scripts/sign-showcase.sh "$app"
ditto -c -k --keepParent "$app" "$work/app.zip"
notary "$work/app.zip" app
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
bash scripts/create-showcase-dmg.sh "$app" "$dmg"
notary "$dmg" dmg
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
(cd "$(dirname "$dmg")" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
