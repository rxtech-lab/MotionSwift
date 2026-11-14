#!/usr/bin/env bash
# Sign Sparkle's nested code inside out; never sign its resource files individually.
set -euo pipefail
app=${1:?Expected app path}
identity=${2:?Expected signing identity}
options=(--force --sign "$identity")
if [[ "$identity" != - ]]; then options+=(--options runtime --timestamp); fi
while IFS= read -r -d '' binary; do
  codesign "${options[@]}" "$binary"
done < <(find "$app/Contents/Frameworks" "$app/Contents/Helpers" \
  -path '*/Sparkle.framework' -prune -o -type f -print0)
framework="$app/Contents/Frameworks/Sparkle.framework"
version="$framework/Versions/Current"
codesign "${options[@]}" "$version/XPCServices/Installer.xpc"
codesign "${options[@]}" --preserve-metadata=entitlements "$version/XPCServices/Downloader.xpc"
codesign "${options[@]}" "$version/Autoupdate"
codesign "${options[@]}" "$version/Updater.app"
codesign "${options[@]}" "$framework"
