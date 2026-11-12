# MotionSwift

A native, Remotion-compatible video rendering engine built with **Swift + Skia**.

The first runnable package compiles Remotion-style TSX with native TypeScript 7 (tsgo), executes React in JavaScriptCore, lays out boxes with Yoga, draws with native Skia, and writes PNG stills or silent H.264 video on macOS. Metal GPU rendering and shared IOSurface hardware H.264 encoding are available on macOS; retained incremental rendering is planned. The same engine is meant to power:

- a **pure SwiftUI visual editor** on macOS/iOS: select a rendered element, drag/resize/rotate it, adjust its timing and duration, and edit animation keyframes on a timeline. Every change is written back to the TSX.
- a **headless cloud render worker** on Linux, replacing Remotion Lambda.

> **Status: runnable Phase 0 package.** Start with [the implemented contract and build instructions](docs/current-implementation.md). The broader compatibility tables and performance figures below remain design targets, not claims about this prototype.

```sh
make bootstrap
make lint test visual
make benchmark
```

## Rendering examples

These stills were rendered by MotionSwift's CPU Skia backend from the [TSX example compositions](tests/compositions/visuals/Boxes.tsx). Each shows frame 15 at 2× scale (640 × 360 pixels). They demonstrate the current Phase 0 shape-rendering subset.

| Boxes and rounded corners | Flex layout |
|---|---|
| ![Orange rectangle and light gray rounded rectangle on a navy background](docs/images/rendering/Boxes.png) | ![Orange, light gray, and red boxes centered in a horizontal flex row](docs/images/rendering/Flex.png) |
| **Opacity and overlapping layers** | **Sequence and spring animation** |
| ![A translucent light gray square overlapping an orange square](docs/images/rendering/Layers.png) | ![An orange square scaled by a spring animation inside a timed sequence](docs/images/rendering/Timed.png) |

Regenerate the screenshots after [building the CLI](docs/current-implementation.md#build-and-commands):

```sh
for composition in Boxes Flex Layers Timed; do
  .build/release/motionswift still --project tests/compositions --entry src/index.ts \
    "$composition" "docs/images/rendering/$composition.png" --frame=15 --backend=cpu --scale=2
done
```

## SDK setup (macOS)

The current Swift package targets **macOS 14+**. Add this checkout as a local package dependency in Xcode and link its **MotionSwift** library product; import the individual modules shown below (there is no umbrella `import MotionSwift`). The showcase includes a visual editor with a shared canvas/timeline controller, object timing, and numeric keyframes; the MotionStudio example also targets iOS/iPadOS. See the [editor contract and limitations](docs/editor.md#available-editor-and-timeline).

First follow the [build prerequisites](docs/current-implementation.md#build-and-commands), then run:

```sh
make bootstrap
make build
```

Run `make compiler native` before building directly in Xcode or with SwiftPM. `make build` and `make showcase` prepare both automatically. Compiler executables and vendor resources are downloaded/generated into the gitignored `Sources/MotionCompiler/Resources/` directory; they are bundled into build output rather than committed to Git. The package locates the resulting native Skia archive relative to its checkout, including when Xcode is launched from Finder. The local archive search path uses a SwiftPM unsafe linker flag, so packages consumed as remote dependencies require a separately distributed binary instead. The compiler bundles native TypeScript 7.0.2 (tsgo) for compilation/type checking and esbuild 0.28.1 for JavaScript bundling for Apple Silicon and Intel. Compilation and type checking need only the project sources: no Node, npm install, repository path, or `MOTIONSWIFT_NODE` setting is required. `Compiler()` loads its tools, React runtime, and type declarations from SwiftPM resources. `Compiler(repository:)` remains source compatible. This macOS implementation launches bundled executables; iOS and signed/sandboxed app distribution need a separate integration and have not been validated. Node is still used by repository development and browser comparison tests.

## SwiftUI preview (macOS)

The `MotionSwiftUI` library previews compositions live in a SwiftUI app. `MotionPlayer` compiles a TSX project (or reuses a compiled bundle), lists its compositions, and renders frames on a dedicated thread that owns a JavaScriptCore runtime and a Skia surface. Rendering never blocks the main thread. While you scrub or play, it renders only the newest requested frame and drops stale ones. Rendered frames are cached (256 MB by default), so replays and scrubbing reuse them.

```swift
import MotionSwiftUI
import SwiftUI

// Drop-in: owns its player, compiles, and autoplays one composition.
struct Preview: View {
    let repository = URL(fileURLWithPath: "/path/to/MotionSwift")
    var body: some View {
        MotionCompositionView(
            source: .project(repository: repository,
                             project: repository.appendingPathComponent("tests/compositions"),
                             entry: "src/index.ts"),
            compositionID: "Timed", showsControls: true)
    }
}

// Or drive the player yourself: transport, props, render settings, layout boxes.
struct Studio: View {
    @State private var player = MotionPlayer(configuration: .init(scale: 2, backend: .gpu))
    let source: MotionSource

    var body: some View {
        MotionPlayerView(player: player, showsLayoutBounds: true)  // or MotionView: preview only
            .task {
                await player.load(source, compositionID: "Motion")
                player.play()
            }
    }
}
// player.seek(to: 12); player.step(by: 1); try player.setProps("{\"title\":\"Hi\"}")
// let frame = try await player.render(frame: 15)  // CGImage + layout boxes + render time
```

Loading and render errors appear as overlays on the preview; unsupported styles stop rendering instead of drawing something wrong. Compilation uses the bundled native tools and project sources. `.bundle(player.bundle!)` reuses a compiled bundle without recompiling.

### Showcase app

`Examples/MotionShowcase` is a small SwiftUI app built on this library. It has a gallery that plays every composition at once (one `MotionCompositionView` per tile), and a composition page with transport controls and an optional layout-bounds overlay. A Render Settings sheet switches backend (CPU or Metal), scale, and looping; an Open Project sheet previews another TSX project folder.

The **Test Film** sidebar destination opens the same checksum-verified project archive used by the benchmark (1080p, 30 fps, 90 seconds). Its preview shows live app RSS and preview peak memory. **Render Test Film** opens a dedicated sheet to save all 2,700 frames as H.264 using Metal, shared IOSurfaces and native VideoToolbox, with worker selection, progress, Stop, and current/peak app RSS. Memory is sampled every 250 ms and includes the app's preview cache; it excludes other processes and separate GPU accounting. Sidebar rows show resolution and FPS.

The preview controls show **Live FPS** (distinct preview-frame deliveries over a rolling second, including cached frames) and **Render FPS** (1000 divided by the displayed frame's render time). The selected composition and Test Film sidebar rows also show Live FPS. Play to measure; the live readout shows a dash while paused or during its initial quarter-second. Playhead jumps do not count skipped frames as delivered frames. The composition's fixed FPS in the header describes the source timeline; Live FPS measures updates delivered to SwiftUI, rather than physical display refreshes.

```sh
make bootstrap   # once
make showcase    # builds and launches the app on tests/compositions
```

## GPU-accelerated rendering with the SDK

Acceleration uses **Skia Ganesh on Metal** for drawing and **VideoToolbox** for hardware H.264 encoding on a compatible Mac. Select `.gpu` explicitly; the default renderer backend is `.cpu`. There is no GPT/AI accelerator setting.

The following function compiles the animated `Motion` fixture and exports every frame as a silent MP4. Call it on a background worker: compilation, the ordered pipeline consumer, and encoder finalization are synchronous. The output's parent directory must exist; an existing regular output file is replaced.

```swift
import Foundation
import MotionCompiler
import MotionRuntime
import MotionRender
import MotionEncode

func renderGPUVideo(repository: URL, output: URL) throws {
    let bundle = try Compiler(repository: repository).compile(
        project: repository.appendingPathComponent("tests/compositions"),
        entry: "src/index.ts")
    let runtime = try Runtime(bundle: bundle)
    guard let composition = try runtime.compositions().first(where: {
        $0.id == "Motion"
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

`FramePipeline` creates a runtime and Metal renderer per worker and delivers frames in presentation order with bounded buffering. `sharedVideoFrames: true` supplies IOSurface-backed buffers to `SharedVideoStream` without application CPU pixel readback or an ffmpeg pipe. A GPU conversion pass still occurs; this does not guarantee that the encoder makes no internal copies. H.264 requires even output pixel dimensions. Metal or hardware-encoder unavailability throws an error; these paths do not silently fall back.

For comparison, `.gpu` with `sharedVideoFrames: false` returns `frame.pixels`. Feed those to `VideoStream(..., encoder: .videotoolbox)` for ffmpeg hardware encoding, or `.software` for libx264; both require ffmpeg and CPU pixel readback. Changing the drawing backend alone does not enable hardware video encoding.

The equivalent CLI command, after the build above, is:

```sh
.build/release/motionswift render --project tests/compositions --entry src/index.ts \
  Motion /tmp/motion-gpu.mp4 --backend=gpu --encoder=videotoolbox-shared \
  --concurrency=2 --report-json=/tmp/motion-gpu.json
```

Use `--backend=cpu --encoder=software` for the CPU/software path. The report records the selected backend, encoder, worker count, and timings. Rendering currently supports the [Phase 0 subset](docs/current-implementation.md#what-runs), including SVG data-URI images with `objectFit: contain`; paragraph text, general image/video decoding, and audio remain planned.

## Documentation

| Document | What it covers |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Modules, data flow, threading, platform backends |
| [docs/implementation-plan.md](docs/implementation-plan.md) | Phases, milestones, exit criteria, risks |
| [docs/typescript-and-packages.md](docs/typescript-and-packages.md) | Native TypeScript compilation, module resolution, JS runtime globals, type-level compatibility, published npm packages |
| [docs/compatibility.md](docs/compatibility.md) | Supported Remotion APIs and CSS subset, plus lint rules |
| [docs/editor.md](docs/editor.md) | Pure SwiftUI editor: selection, drag/resize/rotate, timeline timing and duration, keyframe editing, TSX write-back |
| [docs/performance.md](docs/performance.md) | Speed model, estimates, and how to measure them |
| [docs/benchmark.md](docs/benchmark.md) | Remotion vs native benchmark script and the benchmark comment posted on every PR |
| [tests/README.md](tests/README.md) | Output-check test suite that runs in CI (motion, layout, pixel, and video parity) |

---

## Is Skia the right renderer for Remotion compatibility?

Yes. For these goals (Remotion-style TSX in, fast output, a visual editor), Skia is the best choice.

### Why Skia

Remotion renders with Chrome, and **Chrome draws with Skia**. So Skia gets us closer to Remotion's output than any other option:

| Concern | Skia | Core Animation / Metal direct | Vello / Impeller |
|---|---|---|---|
| Matches Chrome's anti-aliasing, gradients, blur, shadows, blend modes | ✅ same library | ❌ visibly different | ⚠️ close-ish |
| Text shaping (HarfBuzz + ICU via SkParagraph) | ✅ near-Chrome | ⚠️ CoreText breaks lines differently | ⚠️ immature |
| SVG | ✅ SkSVG module | ❌ build it yourself | ⚠️ partial |
| CSS `filter`, `backdrop-filter`, `clip-path`, masks | ✅ image filters, shaders | ⚠️ partial | ⚠️ |
| Multithreaded recording | ✅ Graphite backend | ⚠️ | ✅ |
| Runs on a **Linux server** (cloud render) | ✅ Vulkan or CPU | ❌ Apple only | ✅ |

The last row matters most. The same engine can power the Mac/iOS editor and a cloud render worker, so we don't have to keep Remotion Lambda around.

The main cost is that Skia is C++. Expect a thin C wrapper (or Swift C++ interop) and a heavy build. Budget a week just for build and packaging.

### Keeping the motion identical to the TS code

This is the easy part, as long as we **run the real TSX in JavaScriptCore** and don't translate it:

- `interpolate`, `spring`, and `Easing` are pure math. Implement them in JS that executes in JSC and they produce the same floats as the TS code. Don't port them to Swift, because floating-point drift will make springs diverge. (See [compatibility.md → Motion determinism](docs/compatibility.md#motion-determinism) for the one remaining caveat: `Math.*` functions can differ by an ulp between JSC and V8.)
- A custom React reconciler turns `<div style>` into Skia nodes, with Yoga handling flexbox layout.
- Agent-written Remotion code then runs unchanged as long as it stays inside the supported CSS subset. A lint step rejects unsupported features at generation time, so the agent fixes them before rendering.

**iOS caveat:** in-app JavaScriptCore may run without JIT on iOS, so JS can cost 2–4× more per frame there. This doesn't matter on macOS or on servers.

### UI editing of rendered components

The showcase's **Visual Editor** combines separate `EditorCanvas` and `EditorTimeline` components sharing one `EditorModel`. Select, drag, resize or rotate objects on the canvas; scrub, move and trim object bars on the timeline. Dedicated sheets edit exact timing and numeric keyframes with linear/hold interpolation. Both surfaces share selection, playback, source write-back, hot reload and undo/redo.

Timing and animation are stored as MotionSwift `data-ms-timeline` JSX literals and evaluated in both native previews and exports. Existing code-authored animation expressions remain protected; browser Remotion does not interpret this metadata. See the [implemented editor contract and roadmap](docs/editor.md).

### Speed estimates

> These are engineering estimates, not measurements. Assumptions: 1080p30 on an M-series Mac, Remotion running with its default concurrency, and the native engine using Skia Graphite on Metal with zero-copy IOSurface → VideoToolbox hardware encoding.

#### Where the time goes per frame

| Stage | Remotion (per tab) | Native |
|---|---|---|
| React render (JS) | 1–3 ms | 0.5–2 ms (JSC) |
| Style, layout, paint | 3–10 ms | 0.5–2 ms (Yoga + retained tree) |
| GPU raster | (in paint) | 1–3 ms |
| **Screenshot + PNG/JPEG encode, pipe to ffmpeg, decode** | **10–40 ms** | **~0 ms (zero-copy)** |
| Video encode | software ffmpeg | hardware encoder, 300+ fps ceiling |
| Startup (browser launch, bundle) | 2–5 s | < 0.3 s |

The screenshot/copy round trip is most of Remotion's cost, and the native path removes it entirely.

#### Throughput by composition type (whole machine, all cores)

| Composition type | Remotion | Native (estimate) | Speedup |
|---|---|---|---|
| Text and shape motion graphics | 20–40 fps | 200–400 fps | **8–15×** |
| Images with blur, shadows, gradients | 10–20 fps | 80–200 fps | **5–10×** |
| Video-in-video (`OffthreadVideo`) | 8–15 fps | 60–150 fps (hardware decode) | **5–10×** |
| 4K output | 3–8 fps | 40–100 fps | **10–15×** (the screenshot cost grows with pixel count) |
| Subtrees using the WebKit fallback | – | – | **1–2×** |
| Short clips (< 5 s) | dominated by startup | – | **20×+ wall-clock** |

**Realistic mixed workload: about 5–10× faster renders.** On top of that, editor previews become effectively instant compared with Remotion Studio.

Details and measurement method: [docs/performance.md](docs/performance.md). Every pull request gets a measured Remotion-vs-native comparison posted as a comment ([docs/benchmark.md](docs/benchmark.md)), so these estimates get replaced by real numbers.

### Validate before committing

Do this in the first two weeks (Phase 0 of the [implementation plan](docs/implementation-plan.md)):

1. Pick 5–10 real compositions that Film Studio generates.
2. Profile them in Remotion with `--log=verbose` to get the per-stage breakdown on our hardware.
3. Build a spike that supports only `AbsoluteFill`, `div`, text, images, transforms, and opacity. Render the same compositions and pixel-diff the output against Remotion's.

If the spike shows at least 5× on our own content and acceptable text differences, proceed. If text differences are too visible, invest in SkParagraph tuning before anything else.

The spike's pixel-diff harness is the seed of the permanent CI output-check suite in [`tests/`](tests/README.md).

---

## Planned repository layout

```text
MotionSwift/
├── README.md
├── docs/                      # design docs and plan (this phase)
├── Package.swift              # (planned) SwiftPM root
├── Sources/
│   ├── CSkia/                 # (planned) C shim over Skia, prebuilt binaries
│   ├── MotionCompiler/        # native TypeScript 7 emit/check and JavaScript bundling
│   ├── SkiaKit/               # (planned) Swift wrapper over CSkia
│   ├── MotionLayout/          # (planned) Yoga bindings + style resolution
│   ├── MotionRuntime/         # (planned) JSC host, bridge, frame scheduler
│   ├── MotionRender/          # (planned) retained tree → Skia painter
│   ├── MotionMedia/           # (planned) image/video decode, audio mix, fonts
│   ├── MotionEncode/          # (planned) VideoToolbox / ffmpeg writers
│   ├── MotionEditor/          # shared controller, canvas, timeline and source edit sheets
│   └── motionswift-cli/       # (planned) `motionswift render|still|check`
├── Apps/
│   └── MotionStudio/          # pure SwiftUI editor example (macOS + iOS/iPadOS)
├── js/
│   ├── remotion-shim/         # (planned) @motionswift/remotion: shim + subset .d.ts
│   ├── tsconfig/              # (planned) @motionswift/tsconfig preset
│   ├── cli/                   # (planned) @motionswift/cli npm wrapper for the binary
│   ├── reconciler/            # (planned) react-reconciler host config
│   └── lint/                  # (planned) supported-subset linter
├── .github/workflows/         # (planned) output-check, benchmark (PR comment), goldens, skia-build
└── tests/                     # CI output-check suite + benchmark (structure defined now)
```
