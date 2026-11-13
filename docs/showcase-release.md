# Showcase app releases

Every published GitHub Release (including prereleases) runs
`.github/workflows/showcase-release.yml` and attaches an Apple Silicon DMG and SHA-256 checksum.
The manual **Create a new release** workflow calls the same reusable workflow after semantic-release
publishes. This explicit call is necessary because GitHub suppresses release-event workflows for
releases created with `GITHUB_TOKEN`.

The build checks out the release tag, builds the renderer and SwiftPM executable, compiles the
Icon Composer asset using `actool`, bundles the sample projects and FFmpeg, signs all native code
with Developer ID and hardened runtime, and notarizes/staples the app. It then builds, signs,
notarizes and staples the DMG. Both artifacts must pass Gatekeeper assessment before upload.
Notarization results and rejection logs are retained as Actions artifacts. Failed notarization
never falls back to uploading an unsigned/unnotarized DMG.

CI stamps `CFBundleShortVersionString` from the newly published tag with its `v` prefix removed
(for example, `v1.2.3` becomes `1.2.3`), and `CFBundleVersion` from `GITHUB_RUN_NUMBER`.
The package verifier checks both fields against those expected values before distribution signing
and notarization, so a stale app version fails the release job.

## Required setup

Use a self-hosted `macOS`, `ARM64` runner with Xcode 26 or later, Python 3, GitHub CLI, Homebrew,
and the tools installed by `.github/actions/setup`. The runner must be signed into Xcode's tools
and able to reach Apple's notarization service. Add these Actions secrets:

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Base64 Developer ID Application `.p12`, including its private key |
| `P12_PASSWORD` | Password protecting that `.p12` |
| `SIGNING_CERTIFICATE_NAME` | Full `Developer ID Application: … (TEAMID)` identity |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_ID_PWD` | Apple app-specific password |
| `APPLE_TEAM_ID` | Developer team ID |

No provisioning profile is needed for this app's capabilities. No personal GitHub token is needed.
CI imports the certificate into a temporary keychain, restores the prior keychain search list,
and deletes the certificate/keychain even when a build fails. Configure secrets in repository
settings or with `gh secret set`; do not put their values in source control or chat.

## Local package checks

```sh
VERSION=0.0.0 BUILD_NUMBER=1 make showcase-app
python3 scripts/verify-showcase-package.py .build/showcase/MotionSwift-Showcase-0.0.0-1.app
```

Local packages use ad-hoc signing. Release CI replaces it with Developer ID signing and secure
timestamps. A local package is not a notarized distribution. Output paths are unique by version
and build; use a new build number to retain earlier local packages.

The app includes Gallery, 3D/USDZ examples, the editor sample, Test Film sources, and demo media.
It uses the portable JavaScriptCore compiler, so opening the app does not require a checkout,
Node, npm, or extracted unsigned compiler binaries. Custom projects use the portable compiler's
supported package set; the command-line compiler remains available separately for npm packages.
`MOTIONSWIFT_HOME` still overrides sample lookup for development.

FFmpeg and its non-system libraries are copied into `Contents/Helpers` and `Contents/Frameworks`;
their load commands are rewritten before signing. Installed license files, Homebrew recipes,
and installation receipts are retained under `Contents/Resources/ThirdParty`. These describe the
exact helper sources/build configuration and must be retained with distribution. Homebrew's
FFmpeg is GPL-enabled; maintain corresponding source availability when distributing it.
The app's minimum OS version is raised to the highest deployment target among the packaged
binaries (the initial local Homebrew payload requires macOS 26). This release is arm64 only.

## Icon source

`Examples/AppIcon.icon` is the editable Icon Composer document, with a native midnight-blue
gradient background and the approved orange/coral play ribbon as a separate transparent layer.
It was opened, rendered, and saved in Icon Composer using design generation 26. `actool` produces
`Assets.car` and an `.icns` fallback during each package build.

Xcode's SwiftPM executable scheme and `swift run` do not produce an `.app` bundle. The app sets
its Dock icon from `Examples/MotionShowcase/Media/AppIcon.icns` on the main-loop turn after
foreground activation, so Dock registration cannot replace it with the generic executable icon. The
packaged `.app` uses its compiled Icon Composer assets. After editing the icon, refresh the
development fallback with:

```sh
mkdir -p .build/showcase-icon
xcrun actool Examples/AppIcon.icon --compile .build/showcase-icon --platform macosx \
  --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist .build/showcase-icon/Info.plist --output-format human-readable-text
cp .build/showcase-icon/AppIcon.icns Examples/MotionShowcase/Media/AppIcon.icns
```

The built-in image generation tool produced the style concept and transparent foreground.
Final foreground prompt: extract only the orange/coral folded triangular play ribbon and its
two translucent motion trails from the approved concept; preserve the shape, gradients and
highlights; remove the blue tile and outside background; keep the central triangle transparent;
center on a transparent square with generous padding; no text or extra objects.

References: [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[GitHub token event behavior](https://docs.github.com/en/actions/concepts/security/github_token).
