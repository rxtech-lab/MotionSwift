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
(for example, `v1.2.3` becomes `1.2.3`), and `CFBundleVersion` from `GITHUB_RUN_ID`. Run IDs
increase across the direct release workflow and the reusable workflow's callers, so their
independent workflow run numbers cannot produce conflicting update versions.
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
| `SPARKLE_KEY` | Shared organization Sparkle Ed25519 private signing key, as used by Scanner Buddy/Lumik |

The secret names match Scanner Buddy (`rxtech-lab/lumik`). Ensure the organization secret's
repository access includes `rxtech-lab/MotionSwift`; organization secrets may restrict access.
No provisioning profile is needed for this app's capabilities. The DMG workflow uses `GITHUB_TOKEN`.
CI imports the certificate into a temporary keychain, restores the prior keychain search list,
and deletes the certificate/keychain even when a build fails. Configure secrets in repository
settings or with `gh secret set`; do not put their values in source control or chat.

## Sparkle automatic updates

The showcase links Sparkle 2.10.1 and uses its standard native update dialogs, progress and
installation UI. **MotionSwift Showcase → Check for Updates…** starts a manual check;
Sparkle manages automatic checks and its native consent prompt. Bare `swift run` builds and
local packages without `SPARKLE_PUBLIC_KEY` leave the updater disabled.

CI derives `SUPublicEDKey` from `SPARKLE_KEY` using the same resolver as Scanner Buddy.
An optional `SPARKLE_PUBLIC_KEY` Actions variable (or secret) is checked for consistency.
Keep the existing signing key stable after distributing the app. No private key is embedded.
The framework is copied with symlinks intact and its XPC services, updater app, executable and
framework are signed inside out before the host app is notarized.

Stable releases attach `appcast.xml` after the notarized DMG and checksum are uploaded,
then deploy it to GitHub Pages. The embedded feed is
`https://update.motion.rxfilm.app/appcast.xml`.
Each entry downloads the DMG from its immutable release-tag URL. Sparkle's `generate_appcast`
signs the final stapled DMG; publication verifies its signature against the app's embedded public
key, download URL, byte length, build/marketing versions and actual minimum macOS version.
Prereleases receive DMGs but no stable appcast. Release jobs are serialized.

The previous Pages feed stays available while a new release builds. Deployment happens after
the release assets are uploaded and the new feed is validated.
The feed contains the latest build only; Macs below that build's minimum OS do not receive it.

### GitHub Pages and DNS

Set this repository's Pages source to **GitHub Actions** and its custom domain to
`update.motion.rxfilm.app`. The workflow publishes `appcast.xml`, `.nojekyll`, and a `CNAME`
file containing that domain. For Actions deployments, GitHub's Pages custom-domain setting is
required; the `CNAME` file alone does not configure the domain.

In the `rxfilm.app` DNS zone, add:

| Type | Name | Target |
|---|---|---|
| `CNAME` | `update.motion` | `rxtech-lab.github.io` |

The full record name is `update.motion.rxfilm.app`. Do not include `/MotionSwift` in the target.
Once DNS resolves and GitHub provisions the certificate, enable **Enforce HTTPS** in Pages settings.

For local pipeline checks, install `cryptography>=46,<47` in a Python virtual environment and run:

```sh
python3 scripts/sparkle/test_resolve_key.py
python3 scripts/sparkle/test_appcast.py
```

For end-to-end release verification, install an older signed/notarized app in `/Applications`,
publish a newer stable release, then use **Check for Updates…** to download, install and relaunch.
Source checks and local ad-hoc packages do not establish that production upgrade path.

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

## Showcase UI regression tests

After `make bootstrap`, run `make showcase-ui` (requires Xcode and XcodeGen). The existing
push-only Output check runs this through `make ci`, before the iOS builds can clean native outputs.
The suite packages the release app, verifies its resources and signature, copies it to a temporary
folder outside the checkout, and launches that exact URL with
[XCUIApplication](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication).
It checks rendered gallery frames (including ExternalSVG and USDZ), settings/project sheets,
media transport and nested navigation, study/map/film editors, and the sample editor. Each test
uses a fresh temporary editing workspace, so saved user examples do not affect the results.

The self-hosted runner must run in a logged-in, unlocked macOS desktop session with Xcode UI
automation enabled (`sudo DevToolsSecurity -enable` during runner provisioning). Grant macOS
automation/accessibility permissions to the runner when prompted. A headless LaunchDaemon is
not suitable. UI failures fail CI; there is no headless skip or retry that hides a failing test.
Screenshots, packaging logs and `.xcresult` bundles are uploaded with the existing visual-results
artifact under `tests/reports/showcase-ui/`.
