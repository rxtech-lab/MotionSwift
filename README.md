# MotionSwift

Native motion video rendering and editing with Swift + Skia.

[![Five-second MotionSwift animation with waving lettering, orbiting shapes, and pulsing bars](docs/images/rendering/motionswift.gif)](docs/images/rendering/motionswift.mp4)

## Why we built MotionSwift

Remotion makes video creation through code approachable, especially with AI. Models like GPT and Claude can turn a prompt into a beautiful Remotion composition. We wanted to bring that workflow into our own Swift app.

Rendering was the painful part. Chrome and WebView added bulk, and exporting large 4K videos on a laptop took far too long. We built MotionSwift to give familiar Remotion-style compositions native rendering performance and an editor that feels at home on Apple platforms.

MotionSwift uses Skia under the hood, with Swift APIs, a SwiftUI editor, and Metal rendering with hardware video encoding on macOS. Our goal is faster exports and lower memory use while keeping motion videos editable.

We're working toward 100% compatibility with Remotion, but we're not there yet. Some APIs and styles are unsupported, and rendered output can differ. We're actively developing the framework to close those gaps. See the [current implementation](docs/current-implementation.md) and [compatibility notes](docs/compatibility.md).

## SwiftUI preview

Link the `MotionSwiftUI` package product after following the [build setup](docs/current-implementation.md#build-and-commands). This macOS example previews a composition from the checkout:

```swift
import MotionSwiftUI
import SwiftUI

struct VideoPreview: View {
    let repository = URL(fileURLWithPath: "/path/to/MotionSwift")

    var body: some View {
        MotionCompositionView(
            source: .project(
                repository: repository,
                project: repository.appendingPathComponent("Examples/ReadmeMotion"),
                entry: "src/index.tsx"
            ),
            compositionID: "ReadmeMotion",
            showsControls: true
        )
    }
}
```

## Render

Export a silent H.264 video on macOS using Metal and shared IOSurface buffers with VideoToolbox. Call this function on a background worker; the output directory must exist.

```swift
import Foundation
import MotionCompiler
import MotionRuntime
import MotionRender
import MotionEncode

func renderGPUVideo(repository: URL, output: URL) throws {
    let bundle = try Compiler(repository: repository).compile(
        project: repository.appendingPathComponent("Examples/ReadmeMotion"),
        entry: "src/index.tsx")
    let runtime = try Runtime(bundle: bundle)
    guard let composition = try runtime.compositions().first(where: {
        $0.id == "ReadmeMotion"
    }) else { throw CocoaError(.fileReadCorruptFile) }

    let options = PipelineOptions(workers: 2, backend: .gpu, sharedVideoFrames: true)
    let size = try Renderer.pixelSize(
        width: composition.width, height: composition.height, scale: options.scale)
    let stream = try SharedVideoStream(
        output: output, width: size.width, height: size.height, fps: composition.fps)
    do {
        try FramePipeline.run(
            bundle: bundle, composition: composition,
            frames: Array(0..<composition.durationInFrames), props: "{}", options: options
        ) { frame in
            guard let videoFrame = frame.videoFrame else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try stream.write(videoFrame.pixelBuffer)
        }
        try stream.finish()
    } catch {
        stream.cancel()
        throw error
    }
}

// From a background worker, using your checkout path:
// try renderGPUVideo(repository: URL(fileURLWithPath: "/path/to/MotionSwift"),
//                    output: URL(fileURLWithPath: "/tmp/motion-sdk.mp4"))
```

Or render from the command line after `make bootstrap && make build`:

```sh
.build/release/motionswift render --project Examples/ReadmeMotion --entry src/index.tsx \
  ReadmeMotion /tmp/motion.mp4 --backend=gpu --encoder=videotoolbox-shared --concurrency=2
```

## Open-source Remotion examples in SwiftUI

The macOS showcase bundles **12 MIT-licensed open-source Remotion compositions** from four community repositories ([`Alexwtlf/agentic-product-demo`](https://github.com/Alexwtlf/agentic-product-demo), [`zz41354899/SwiftClip`](https://github.com/zz41354899/SwiftClip), [`RenderComp/free-remotion-templates`](https://github.com/RenderComp/free-remotion-templates), and [`lifeprompt-team/remotion-scenes`](https://github.com/lifeprompt-team/remotion-scenes)) — including five compositions whose upstream TSX runs unchanged. Launch directly into the gallery with `MOTIONSWIFT_SHOWCASE_START=open-source make showcase`.

![Four open-source MIT Remotion compositions rendered natively by MotionSwift with Metal](docs/images/rendering/OpenSourceSwiftUI.gif)

Opening any card loads a working copy into SwiftUI's `MotionEditorView`, with live Metal playback, canvas hit-testing, inline text and style inspection, and a scrubbable multitrack timeline:

![MotionEditorView inspecting Acme Studio Product Demo in SwiftUI on macOS](docs/images/rendering/OpenSourceShowcaseSwiftUI.png)

### Visual comparison: Remotion (Chrome) vs. MotionSwift (SwiftUI + Metal)

Full-resolution frames rendered from the same `Examples/MotionShowcase/OpenSource/index.tsx` entry by Chrome Remotion (`@remotion/renderer`) and MotionSwift (`Skia Metal`):

| Composition | Remotion (Chrome) | MotionSwift (SwiftUI + Metal) |
|---|---|---|
| **Acme Studio Product Demo**<br>`Alexwtlf/agentic-product-demo` · 1600×1000<br>OKLab token ramps, typing, SVG cursor, press physics | ![ProductDemo in Remotion](docs/images/rendering/OpenSource-ProductDemo-remotion.png) | ![ProductDemo in MotionSwift](docs/images/rendering/OpenSource-ProductDemo-motionswift.png) |
| **Dynamic Island Call Pill** *(unmodified TSX)*<br>`zz41354899/SwiftClip` · 1920×1080<br>Chained springs, 135° gradient avatar, drop shadow | ![DynamicIsland in Remotion](docs/images/rendering/OpenSource-DynamicIsland-remotion.png) | ![DynamicIsland in MotionSwift](docs/images/rendering/OpenSource-DynamicIsland-motionswift.png) |
| **Broadcast Lower-Third Glass Card**<br>`RenderComp/free-remotion-templates` · 1920×1080<br>`backdropFilter: blur(14px)`, radial glow, rounded clip | ![LowerThirdGlassCard in Remotion](docs/images/rendering/OpenSource-LowerThirdGlassCard-remotion.png) | ![LowerThirdGlassCard in MotionSwift](docs/images/rendering/OpenSource-LowerThirdGlassCard-motionswift.png) |
| **Quarterly Revenue Bar Chart** *(unmodified TSX)*<br>`RenderComp/free-remotion-templates` · 1920×1080<br>Staggered spring bars, 4-corner `borderRadius` | ![BarChartAnim in Remotion](docs/images/rendering/OpenSource-BarChartAnim-remotion.png) | ![BarChartAnim in MotionSwift](docs/images/rendering/OpenSource-BarChartAnim-motionswift.png) |
| **Northern Lights Aurora**<br>`lifeprompt-team/remotion-scenes` · 1920×1080<br>Rotating blurred radial curtains, `random(seed)` stars | ![BackgroundAurora in Remotion](docs/images/rendering/OpenSource-BackgroundAurora-remotion.png) | ![BackgroundAurora in MotionSwift](docs/images/rendering/OpenSource-BackgroundAurora-motionswift.png) |
| **Gradient Circular Progress**<br>`lifeprompt-team/remotion-scenes` · 1920×1080<br>Rotated SVG `strokeDashoffset` ring + `linearGradient` | ![ShapeCircularProgress in Remotion](docs/images/rendering/OpenSource-ShapeCircularProgress-remotion.png) | ![ShapeCircularProgress in MotionSwift](docs/images/rendering/OpenSource-ShapeCircularProgress-motionswift.png) |

### Open-source clip export speed & parity

End-to-end full-resolution H.264 exports on an Apple M4 Max (8 workers per engine, cold start including bundling/compilation and encoding):

| Open-source clip | Resolution · Frames | Remotion (x264) | MotionSwift (Metal + Shared VideoToolbox) | Video SSIM | Peak RSS (Remotion → MotionSwift) |
|---|---|---:|---:|---:|---:|
| `BarChartAnim` *(unmodified)* | 1920×1080 · 150f | 19.94 s | **2.04 s** (9.78× faster) | 0.9965 | 3,335 MiB → 778 MiB (−76.7%) |
| `BackgroundAurora` | 1920×1080 · 120f | 15.36 s | **1.87 s** (8.21× faster) | 0.9947 | 3,457 MiB → 194 MiB (−94.4%) |
| `DynamicIsland` *(unmodified)* | 1920×1080 · 150f | 19.84 s | **2.68 s** (7.40× faster) | 0.9995 | 3,401 MiB → 573 MiB (−83.1%) |
| `LowerThirdGlassCard` | 1920×1080 · 120f | 16.91 s | **2.43 s** (6.95× faster) | 0.9963 | 3,547 MiB → 368 MiB (−89.6%) |
| `ShapeCircularProgress` | 1920×1080 · 90f | 13.79 s | **2.09 s** (6.61× faster) | 0.9980 | 2,608 MiB → 147 MiB (−94.4%) |
| `ProductDemo` (`200-319`) | 1600×1000 · 120f | 17.64 s | **11.20 s** (1.58× faster) | 0.9529 | 3,271 MiB → 554 MiB (−83.1%) |

Across all 6 clips, MotionSwift exported **5.92× faster** (geometric mean; **7.71×** across the five 1080p templates) while using **76.7%–94.4% less process-tree memory**. See [full 12-composition parity & reproduction](docs/benchmarks/2026-11-14-open-source.md) and bundled MIT notices in [`Examples/MotionShowcase/OpenSource/THIRD-PARTY-LICENSES.txt`](Examples/MotionShowcase/OpenSource/THIRD-PARTY-LICENSES.txt).

## Performance compared with Remotion

MotionSwift exported **17.24× faster with Metal + x264** and **18.89× faster with CPU + x264** across 12 short synthetic cases (geometric means).

| Measurement | Remotion | MotionSwift | Improvement |
|---|---:|---:|---:|
| 720p boxes, 30 frames: CPU + x264 export | 9.248 s | 0.409 s | 22.63× faster |
| 720p boxes, 30 frames: Metal + x264 export | 9.248 s | 0.421 s | 21.97× faster |
| 720p boxes, 30 frames: Metal + shared IOSurface / VideoToolbox export | 9.248 s | 0.459 s | 20.15× faster |
| Same boxes clip: peak process-tree RSS, shared IOSurface path | 2,520.2 MiB | 255.5 MiB | 89.9% lower |

Measured on an Apple M4 Max (16 cores, 128 GB), eight workers per engine, one run without warmup. Export times include startup, compilation/bundling and encoding. All cases passed SSIM ≥ 0.98; hardware/software quality settings differ. These short synthetic results do not establish full-film or 4K speedups over Remotion. RSS is sampled and excludes separate GPU/media-engine accounting.

[Comparison results and reproduction](docs/benchmarks/2026-11-12-remotion-comparison.md) · [Memory measurements](docs/benchmarks/2026-11-12-memory.md) · [Open-source examples benchmark](docs/benchmarks/2026-11-14-open-source.md).

### 3D scenes with three.js and USDZ

`@remotion/three` compositions render natively. `<ThreeCanvas>` scenes written with React Three Fiber elements run through a Metal port of three.js's shading. The scenes can use keyframed cameras, moving and rotating meshes, animated lights, fog, transparency and USDZ models loaded with `useLoader(USDLoader, staticFile(...))`. On three complex test scenes (up to 1,200+ meshes and a 13× instanced USDZ model), native export was **11.5× faster than Remotion** (geometric mean, 360p and 1080p). Still frames stay within a PSNR ≥ 48 dB gate of Remotion's three.js output.

| Crystal Orbit | Neon City | Probe Fleet (USDZ) |
|---|---|---|
| ![Crystal Orbit](docs/images/rendering/ThreeCrystalOrbit.png) | ![Neon City](docs/images/rendering/ThreeNeonCity.png) | ![Probe Fleet](docs/images/rendering/ThreeProbeFleet.png) |

The showcase's **3D Scenes** page plays all of them live (`MOTIONSWIFT_SHOWCASE_START=3d make showcase`). See [3D support](docs/three-d.md) for the API subset and the [3D benchmark](docs/benchmarks/2026-11-13-three.md).

### Compose smaller clips with media

The showcase's **Media Composition** page opens a 24-second master containing reusable montage,
image and video compositions. Double-click a nested composition on the canvas or timeline to
open it; return through the breadcrumbs with the parent's playhead preserved. Playback controls,
mute, a scrubbable multitrack timeline, and an export sheet follow the selected composition. See [nested clips and media](docs/media-compositions.md) for the supported APIs and limits.

The macOS showcase can also be packaged as a standalone app with `make showcase-app`.
Published releases build a Developer ID signed, notarized DMG once the required credentials are
configured. See [showcase release setup and icon source](docs/showcase-release.md).

## License

MotionSwift's original source code is available under the [MIT License](LICENSE).
Third-party dependencies and bundled tools retain their own licenses; the MIT
License does not replace their license terms or notices.
