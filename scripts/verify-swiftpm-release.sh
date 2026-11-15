#!/usr/bin/env bash
# Build a consumer from a clean Git checkout, without running consumer-side bootstrap.
# Optional URL/tag arguments verify an already published release instead of the working tree.
# MOTIONSWIFT_SMOKE_LOCAL_NATIVE=1 stages the candidate binary before its URL exists.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/motionswift-consumer.XXXXXX")
if [[ "${MOTIONSWIFT_KEEP_SMOKE:-0}" == 1 ]]; then
  echo "Retained consumer directory: $work"
else
  trap 'rm -rf "$work"' EXIT
fi
if [[ $# == 0 ]]; then
  python3 - "$work/MotionSwift" <<'PY'
from pathlib import Path
import shutil
import subprocess
import sys
import os

destination = Path(sys.argv[1])
# Match the source and generated assets committed by @semantic-release/git.
paths = subprocess.check_output(['git', 'ls-files', '-z', 'Package.swift', 'Sources',
                                 'Examples/MotionShowcase', 'tests/Swift', 'tests/Showcase']).split(b'\0')
for raw in paths:
    if not raw:
        continue
    source = Path(raw.decode())
    target = destination / source
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
for directory in ['Sources/MotionCompiler/Resources', 'Sources/MotionPortable/JavaScript']:
    shutil.copytree(directory, destination / directory, dirs_exist_ok=True)
assert not (destination / 'native/MotionSwiftNative.xcframework').exists()
if os.environ.get('MOTIONSWIFT_SMOKE_LOCAL_NATIVE') == '1':
    shutil.copytree('native/MotionSwiftNative.xcframework', destination / 'native/MotionSwiftNative.xcframework')
PY
  git -C "$work/MotionSwift" init -q
  git -C "$work/MotionSwift" add -f .
  git -C "$work/MotionSwift" -c commit.gpgsign=false -c user.name=CI -c user.email=ci@example.invalid commit -qm 'Prepared SwiftPM release'
  git -C "$work/MotionSwift" -c tag.gpgSign=false tag v0.0.0
  package_url="file://$work/MotionSwift"
  package_version=0.0.0
else
  package_url=${1:?Package URL}
  package_version=${2:?Release version}
  package_version=${package_version#v}
fi
mkdir -p "$work/consumer/Sources/Smoke"
export MOTIONSWIFT_SMOKE_URL="$package_url" MOTIONSWIFT_SMOKE_VERSION="$package_version"
python3 - "$work/consumer" <<'PY'
import json
import os
from pathlib import Path
import sys

root = Path(sys.argv[1])
url = json.dumps(os.environ['MOTIONSWIFT_SMOKE_URL'])
version = json.dumps(os.environ['MOTIONSWIFT_SMOKE_VERSION'])
root.joinpath('Package.swift').write_text(f'''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Consumer", platforms: [.macOS(.v14)], dependencies: [
  .package(url: {url}, exact: {version}),
], targets: [.executableTarget(name: "Smoke", dependencies: [
  .product(name: "MotionSwift", package: "MotionSwift"),
  .product(name: "MotionCompiler", package: "MotionSwift"),
])])
''')
root.joinpath('Sources/Smoke/main.swift').write_text('''import Foundation
import MotionCompiler
import MotionPortable
import SkiaKit

let portable = try PortableCompiler()
_ = try portable.compile(files: ["index.ts": "export const answer: number = 42"], entry: "index.ts")
precondition(Vendor.identity != "unavailable")
let project = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: project) }
try "export const answer: number = 42".write(to: project.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
_ = try Compiler().graph(project: project, entry: "index.ts")
let canvas = try Canvas(width: 8, height: 8)
canvas.clear()
print("Remote package: native binary, portable compiler and macOS toolchains passed")
''')
root.joinpath('project.yml').write_text(f'''name: Consumer
packages:
  MotionSwift:
    url: {url}
    exactVersion: {version}
targets:
  Consumer:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources: [App.swift]
    dependencies:
      - package: MotionSwift
        product: MotionSwift
      - package: MotionSwift
        product: MotionCompiler
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: app.rxlab.motionswift.consumer
        SWIFT_VERSION: "6.0"
''')
root.joinpath('App.swift').write_text('''import SwiftUI
import MotionSwiftUI
import MotionCompiler
import MotionPortable
@main struct Consumer: App {
  var body: some Scene { WindowGroup { Text("MotionSwift consumer") } }
}
''')
PY
swift run --package-path "$work/consumer" Smoke
xcodegen generate --quiet --spec "$work/consumer/project.yml"
xcodebuild -project "$work/consumer/Consumer.xcodeproj" -scheme Consumer \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$work/DerivedData" build CODE_SIGNING_ALLOWED=NO -quiet
