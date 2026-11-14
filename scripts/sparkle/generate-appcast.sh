#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${SPARKLE_KEY:?Missing shared Sparkle signing secret}"
: "${RELEASE_TAG:?Missing release tag}"
[[ "$RELEASE_TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo 'Only stable releases may publish the update feed' >&2; exit 1;
}
app=${1:?Expected app path}
archive=${2:?Expected notarized DMG path}
output=${3:?Expected appcast output path}
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/showcase-appcast.XXXXXX")
trap 'rm -rf "$work"' EXIT
cp "$archive" "$work/$(basename "$archive")"
prefix="https://github.com/rxtech-lab/MotionSwift/releases/download/$RELEASE_TAG/"
printf '%s' "$SPARKLE_KEY" | .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  "$work" --ed-key-file - --maximum-deltas 0 --download-url-prefix "$prefix" \
  --link "https://github.com/rxtech-lab/MotionSwift/releases/tag/$RELEASE_TAG"
python3 scripts/sparkle/validate-appcast.py "$work/appcast.xml" "$archive" \
  "$app/Contents/Info.plist" "$RELEASE_TAG"
cp "$work/appcast.xml" "$output"
