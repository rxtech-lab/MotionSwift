# Native XCFramework releases

`Create a new release` calls `Build XCFramework` after semantic-release publishes a
version. It builds the Rust/Skia native library from that release tag, signs the
XCFramework, and uploads these assets to the same GitHub Release:

- `MotionSwiftNative-vX.Y.Z.xcframework.zip`
- `MotionSwiftNative-vX.Y.Z.xcframework.zip.sha256`

The checksum is generated with `swift package compute-checksum`. The signed ZIP
contains `MotionSwiftNative.xcframework` at its root, with macOS arm64 (14+), iOS
device arm64 (17+), and iOS simulator arm64 (17+) static library slices. Packaging
rejects missing slices. Intel Macs and Intel iOS simulators are not included.

Like the Showcase release, the build uses a self-hosted macOS ARM64 runner with
full Xcode, Python 3, GitHub CLI, and Rust build prerequisites. It reuses the
`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, and `SIGNING_CERTIFICATE_NAME` repository
secrets. The signing keychain is unique to each run and removed afterward.

To build assets for an existing published release after this workflow is merged:

```bash
gh workflow run build-xcframework.yml --ref main -f release_tag=v1.0.0
```

The workflow checks out the requested tag. That tag must contain the build and
packaging scripts, so releases predating this setup need a new release or a
backport before they can use it. A successful rerun replaces the assets for that
tag. The workflow is called directly by Create Release rather than also listening
for release events, which avoids duplicate builds.

This distributes the `MotionSwiftNative` binary target. The public Swift modules
remain source targets in the main package; `Package.swift` continues to use the
local native XCFramework for development. The release does not automatically
rewrite the manifest to a remote binary URL.

For local packaging after `make native-ios`:

```bash
bash scripts/package-xcframework.sh v1.0.0 /tmp/motionswift-release
```
