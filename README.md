# MotionSwift

A native, Remotion-compatible video rendering engine built with **Swift + Skia**.

The first runnable package compiles Remotion-style TSX with SWC, executes React in JavaScriptCore, lays out boxes with Yoga, draws with native Skia, and writes PNG stills or silent H.264 video on macOS. Retained incremental rendering and zero-copy hardware encoding are planned. The same engine is meant to power:

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

## Documentation

| Document | What it covers |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Modules, data flow, threading, platform backends |
| [docs/implementation-plan.md](docs/implementation-plan.md) | Phases, milestones, exit criteria, risks |
| [docs/typescript-and-packages.md](docs/typescript-and-packages.md) | TS compilation (swc on every platform), module resolution, JS runtime globals, type-level compatibility, published npm packages |
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

The editor is **pure SwiftUI**: a preview canvas with drag, resize, and rotate handles, a timeline for sequence timing and duration, keyframe lanes for animations, and an inspector. Because the render tree is retained (not screenshotted pixels), editing fits naturally:

1. The compiler (swc) stamps each JSX element with its source location (file:line:col).
2. On click, a native hit test finds the node and its source location, and the inspector shows its props and style.
3. Canvas gestures (drag, resize, rotate) and timeline edits (moving a `Sequence`, changing its duration, editing keyframes and easing) become edit operations. They're written back to the TSX through an AST transform (ts-morph), then hot-reloaded.
   - Static props (color, text, position, rotation) rewrite the literal.
   - Animated props (`interpolate(frame, [0, 30], [0, 1])`, `spring(...)`) appear as keyframes. A gesture on an animated property edits or inserts the keyframe at the playhead.
4. While a gesture is in progress, a preview override keeps feedback under one frame. Scrubbing renders a single frame in a few milliseconds.

Details: [docs/editor.md](docs/editor.md).

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
│   ├── MotionCompiler/        # (planned) swc-based TS/TSX compiler (Rust, C ABI, prebuilt)
│   ├── SkiaKit/               # (planned) Swift wrapper over CSkia
│   ├── MotionLayout/          # (planned) Yoga bindings + style resolution
│   ├── MotionRuntime/         # (planned) JSC host, bridge, frame scheduler
│   ├── MotionRender/          # (planned) retained tree → Skia painter
│   ├── MotionMedia/           # (planned) image/video decode, audio mix, fonts
│   ├── MotionEncode/          # (planned) VideoToolbox / ffmpeg writers
│   ├── MotionEditor/          # (planned) hit testing, gesture → edit ops, timeline model
│   └── motionswift-cli/       # (planned) `motionswift render|still|check`
├── Apps/
│   └── MotionStudio/          # (planned) pure SwiftUI editor app (macOS + iOS/iPadOS)
├── compiler/                  # (planned) Rust crate on swc_core: TS strip, JSX, source stamp
├── js/
│   ├── remotion-shim/         # (planned) @motionswift/remotion: shim + subset .d.ts
│   ├── tsconfig/              # (planned) @motionswift/tsconfig preset
│   ├── cli/                   # (planned) @motionswift/cli npm wrapper for the binary
│   ├── reconciler/            # (planned) react-reconciler host config
│   └── lint/                  # (planned) supported-subset linter
├── .github/workflows/         # (planned) output-check, benchmark (PR comment), goldens, skia-build
└── tests/                     # CI output-check suite + benchmark (structure defined now)
```
