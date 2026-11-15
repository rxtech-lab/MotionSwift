# SwiftPM and native XCFramework releases

`Create a new release` prepares a consumable Swift package before semantic-release
creates the version tag. On the self-hosted macOS ARM64 runner, preparation:

1. Generates the macOS compiler toolchains/vendor resources and portable JavaScript resources.
2. Builds the Rust/Skia XCFramework for macOS arm64 (14+), iOS device arm64 (17+),
   and iOS simulator arm64 (17+), then signs and verifies it.
3. Packages the signed binary and writes its versioned URL and SwiftPM checksum
   into `Package.swift`.
4. Builds and runs a clean Git consumer using the candidate binary, then commits
   the manifest and generated resources with `@semantic-release/git`,
   including the otherwise ignored resource directories, so the release tag
   contains everything a clean consumer needs.
5. Uploads the exact archive used for the checksum through `@semantic-release/github`:
   `MotionSwiftNative-vX.Y.Z.xcframework.zip` and the matching `.zip.sha256` file.

Swift modules remain source targets. A bootstrapped development checkout uses
its local `native/MotionSwiftNative.xcframework`; a clean checkout downloads the
versioned binary. Consumers do not run Node, npm, Rust or `make bootstrap`.
Intel Macs and Intel iOS simulators are not included.

The release uses `RELEASE_TOKEN` for its automated release commit/tag and assets,
and `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, and `SIGNING_CERTIFICATE_NAME` for
signing. Its temporary signing keychain is removed on success or failure.

Push CI checks a clean Git consumer with the candidate native binary staged in
the test repository, so native API changes can be tested before publication.
After publishing, release CI fetches the actual GitHub tag and binary URL,
executes the portable compiler and native macOS compiler, allocates a Skia
surface, and builds a macOS Xcode app. This checks runtime resource availability
as well as package resolution and linking. Native source changes also pass the
existing local native build/test checks before release.

To run the consumer checks locally after `make compiler`:

```bash
bash scripts/verify-swiftpm-release.sh
# Test a candidate native binary that has not been published yet:
MOTIONSWIFT_SMOKE_LOCAL_NATIVE=1 bash scripts/verify-swiftpm-release.sh
# Or test an already published release, without copying local resources:
bash scripts/verify-swiftpm-release.sh https://github.com/rxtech-lab/MotionSwift.git vX.Y.Z
```

`Build XCFramework` remains a manual recovery workflow for legacy releases that
lack native assets. It never overwrites published assets and rejects an archive
whose checksum differs from the tagged manifest. Publish a new release to change
an archive or fix a tagged manifest; rebuilding a signed archive can change its
bytes and invalidate consumers' checksums.

Existing v1.1.1 source tags still lack the remote manifest and compiler resources.
These changes require a new release before Film Workflow can consume them from
GitHub. Do not repoint the existing tag.

For standalone local packaging after `make native-ios`:

```bash
bash scripts/package-xcframework.sh v1.0.0 /tmp/motionswift-release
```
