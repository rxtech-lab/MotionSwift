#!/usr/bin/env bash
# semantic-release prepare: the ZIP checksum and tagged manifest must describe the SAME bytes.
set -euo pipefail
cd "$(dirname "$0")/.."
tag=${1:?Usage: prepare-swiftpm-release.sh RELEASE_TAG}
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]
make compiler native-ios
if [[ -n "${SIGNING_CERTIFICATE_NAME:-}" ]]; then
  codesign --force --timestamp --sign "$SIGNING_CERTIFICATE_NAME" native/MotionSwiftNative.xcframework
  codesign --verify --strict --verbose=2 native/MotionSwiftNative.xcframework
elif [[ "${CI:-}" == true ]]; then
  echo 'Release CI requires SIGNING_CERTIFICATE_NAME' >&2
  exit 1
fi
python3 - <<'PY'
from pathlib import Path
for old in Path('.build/swiftpm-release').glob('MotionSwiftNative-*'):
    if old.is_file():
        old.unlink()
PY
bash scripts/package-xcframework.sh "$tag" "$PWD/.build/swiftpm-release"
python3 - "$tag" <<'PY'
from pathlib import Path
import re
import sys

tag = sys.argv[1]
checksum = Path(f'.build/swiftpm-release/MotionSwiftNative-{tag}.xcframework.zip.sha256').read_text().split()[0]
manifest = Path('Package.swift')
source = manifest.read_text()
for key, value in [('nativeReleaseTag', tag), ('nativeReleaseChecksum', checksum)]:
    source, count = re.subn(rf'let {key} = "[^"]+"', f'let {key} = "{value}"', source)
    assert count == 1, f'Missing or duplicate {key}'
manifest.write_text(source)
PY
