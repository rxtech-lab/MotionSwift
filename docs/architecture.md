# Architecture

> Current executable behavior and remaining work: [runnable implementation](current-implementation.md). This document describes the target architecture and roadmap.

## Goals and non-goals

**Goals**

- Render Remotion compositions (TSX) to video with output that is visually indistinguishable from Remotion's, within the [supported subset](compatibility.md).
- Run 5–10× faster than Remotion on the same hardware ([performance.md](performance.md)).
- One engine for three hosts: macOS editor, iOS editor/preview, and a Linux headless render worker.
- Keep a retained, source-mapped render tree so the editor can hit-test and edit rendered elements ([editor.md](editor.md)).

**Non-goals**

- Being a general web browser. Unsupported HTML/CSS is rejected by lint or routed to the WebKit fallback (macOS only). We don't emulate it.
- Porting Remotion's motion math to Swift. All user-visible math runs in JS.
- Supporting Remotion's Node-side APIs (`@remotion/renderer`, `@remotion/lambda`). We replace them.

## High-level data flow

```text
 TSX project
     │  MotionCompiler (tsgo): strip types and transform JSX; source stamps planned
     │  resolver: alias `remotion` → @motionswift/remotion, allowlist, node_modules
     ▼
 module graph ──────────────────────────────────────────────────────────────┐
                                                                          │
 ┌─────────────────────────── per render worker ───────────────────────┐ │
 │                                                                      │◄┘
 │  MotionRuntime (JSContext)                                           │
 │    setFrame(n) → React render → reconciler commit                    │
 │        │  batched mutation ops (Float64/Uint32 buffer, no per-op FFI)│
 │        ▼                                                             │
 │  Retained node tree (Swift)  ── style resolve ──► MotionLayout (Yoga)│
 │        │                                                             │
 │        ▼                                                             │
 │  MotionRender: paint tree → SkPicture / Graphite Recording           │
 │        │      (waits on delayRender handles from MotionMedia)        │
 │        ▼                                                             │
 │  Raster target                                                       │
 │    macOS/iOS: Graphite-Metal → IOSurface-backed MTLTexture           │
 │    Linux:     Graphite-Vulkan or CPU raster → DMA-BUF / RAM buffer   │
 │        │                                                             │
 └────────┼─────────────────────────────────────────────────────────────┘
          ▼
 MotionEncode
   Apple: CVPixelBuffer(IOSurface) → VTCompressionSession → AVAssetWriter
   Linux: ffmpeg (libavcodec, NVENC/VAAPI if present, else x264)
   Audio: MotionMedia mixer → AAC → mux
```

## Modules

| Module | Language | Responsibility |
|---|---|---|
| `MotionCompiler` | Native TypeScript 7 (tsgo) + Swift | TS/TSX → JS emission and type checking; esbuild links emitted JavaScript. Current subprocess integration is macOS-only. Portable packaging and source maps remain planned. See [typescript-and-packages.md](typescript-and-packages.md). |
| `CSkia` | C / C++ | A narrow C ABI (`msk_*` functions) over the Skia features we use: canvas, paint, path, shaders, image filters, SkParagraph, SkSVG, Graphite context/recorder. Shipped as a prebuilt XCFramework (Apple) and `.so` (Linux). |
| `SkiaKit` | Swift | Safe Swift wrappers (`~Copyable` handles, `deinit` release) over `CSkia`. No engine logic. |
| `MotionLayout` | Swift + Yoga (C) | CSS style parsing for the supported subset, cascade-free style resolution (inline styles only), Yoga node sync, and computing absolute boxes and transforms. |
| `MotionRuntime` | Swift + JS | JSContext lifecycle, module loader for the compiled module graph, web-like globals (`fetch`, timers, `URL`, ...), host bridge (op buffer and asset callbacks), `delayRender` bookkeeping, frame scheduler. |
| `MotionRender` | Swift | Walks the laid-out tree and emits Skia draw calls: backgrounds, borders, radii, shadows, gradients, clipping, opacity layers, filters, blend modes, text, SVG, images, video frames. |
| `MotionMedia` | Swift | Image decode (ImageIO / libwebp/libpng on Linux), video frame extraction (AVFoundation + VideoToolbox; ffmpeg on Linux), font registration (`loadFont`, `@remotion/google-fonts`), audio decode and mix. |
| `MotionEncode` | Swift | Video/audio writers per platform; codec and bitrate presets mapped from Remotion's `--codec`, `--crf`, `--pixel-format`. |
| `MotionEditor` | Swift | Hit testing, property classification, gesture → edit-operation mapping (drag/resize/rotate), the timeline model (sequence tree and keyframes), preview overrides, and the edit-operation protocol to the AST service ([editor.md](editor.md)). UI-free, so it can be unit tested. |
| `MotionStudio` | SwiftUI | The editor app for macOS and iOS/iPadOS: canvas overlay handles, timeline, inspector, and sheets. Pure SwiftUI, except the Metal preview surface, which is wrapped in a representable. |
| `motionswift-cli` | Swift | `render`, `still`, `check`, `trace`, `compare` commands. The CI suite and the PR benchmark drive this ([benchmark.md](benchmark.md#native-cli-contract)). |
| `js/remotion-shim` | TS | Drop-in replacement for the `remotion` package ([compatibility.md](compatibility.md)). |
| `js/reconciler` | TS | `react-reconciler` host config that serializes mutations into the op buffer. |
| Source stamp (planned) | TBD | Adds `data-ms-src="file:line:col"` to host JSX elements. iOS integration remains unimplemented. |
| `js/lint` | TS | ESLint plugin and TS type check that reject unsupported APIs and CSS. |

## The JS ↔ native bridge

Per-node FFI calls through JSC are slow (each call crosses the JS/C boundary). Instead:

The current worker uses a deterministic batch of `create`, `patch`, `children`, and
`delete` operations returned through one JSC call. It diffs the settled host output
against the retained JS tree, sends only changed style keys and properties, and
applies the batch to retained Swift nodes. Unchanged native `RenderNode` subtrees
are cached; mutations invalidate that node and every ancestor. There is no
per-frame full-tree JSON encoding/decoding. Paths provide deterministic host IDs;
React keys still determine component identity within a sample.

The VM, parsed graph definitions, React and reconciler are retained. User module
caches and React roots are reset for **each** sample, including sequential playback:
module counters, random initializers and hooks must not depend on prior samples.
React effects and state updates may settle within that sample. Props/composition
changes clear both retained trees; new source requires a new `Runtime(bundle:)`.
`Runtime.invalidate()` explicitly clears retained output. This implementation
reuses native output subtrees, not layout results or SkPictures. A shared binary
`ArrayBuffer` with interned strings and direct reconciler mutation recording remains
a future transport optimization; the present bridge uses JSC arrays.

## Frame lifecycle

```text
setFrame(n)
  → reset user modules, lifecycle queues and React state
  → JS: update the frame context, flushSync(render)   # React render + commit
  → flush effects, microtasks and deterministic timers until delayRender handles settle
  → native: apply mutation batch; invalidate changed subtree snapshots
  → Yoga calculateLayout
  → paint dirty subtrees → record (cached SkPictures for clean subtrees)
  → raster → hand the GPU surface to the encoder (no CPU readback)
```

SkPicture and incremental Yoga caching remain targets. Currently only unchanged native render-tree subtrees are reused.

## Preview overrides (editor)

During a canvas gesture, the editor sends `nodeId → style patch` overrides to the preview worker. They're applied after reconciliation and before layout, so feedback stays under one frame without writing files. Overrides are cleared once the edit is written to source and recompiled. See [editor.md](editor.md#3-canvas-editing-drag-resize-rotate).

## Concurrency model

- **Render workers.** Like Remotion's `--concurrency`, the frame range is split into contiguous chunks. Each worker owns its own `JSVirtualMachine` + `JSContext` (JSC contexts are single-threaded), its own retained tree, and a Graphite `Recorder`.
- **Shared.** One Graphite `Context` per GPU, a font collection shared read-only, and a decoded-image cache with refcounted, immutable `SkImage`s.
- **Encoding.** Workers produce frames out of order. A reorder buffer feeds the single encoder in order. For very long renders, each chunk can be encoded as its own segment and concatenated (GOP-aligned), which removes the ordering bottleneck.
- **Determinism rule.** Any frame `n` must render identically no matter which worker renders it or what frame came before. This is enforced in CI by rendering frames in shuffled order and comparing ([tests/README.md](../tests/README.md)).

## Platform backends

| | macOS | iOS | Linux worker |
|---|---|---|---|
| JS engine | JavaScriptCore (system, JIT) | JavaScriptCore (system, usually no JIT in-app) | JavaScriptCore (`libjavascriptcoregtk`, pinned version) |
| Raster | Graphite-Metal | Graphite-Metal | Graphite-Vulkan, or Skia CPU raster when there is no GPU |
| Zero-copy path | IOSurface → CVPixelBuffer | IOSurface → CVPixelBuffer | Vulkan → DMA-BUF → VAAPI/NVENC where available; otherwise readback |
| Video decode | VideoToolbox | VideoToolbox | ffmpeg (hardware decode if available) |
| Encode | VideoToolbox (H.264/HEVC/ProRes) | VideoToolbox | ffmpeg (x264/x265/NVENC/VAAPI) |
| WebKit fallback | `WKWebView` snapshot (opt-in) | ✗ | ✗ (rejected by lint) |

JSC is used on Linux too (instead of QuickJS or V8) so that the editor, the iOS preview, and cloud renders produce the same float results for the same bundle.

## Skia build and packaging

- Pin one Skia milestone (`chrome/mXXX`) and record it in `third_party/skia.lock`. Prefer the milestone shipped by the Chrome Headless Shell version Remotion pins, so Skia raster behavior matches the golden generator.
- Build with `gn` and these flags: `skia_use_metal` (Apple), `skia_use_vulkan` (Linux), `skia_enable_graphite=true`, `skia_use_icu`, `skia_use_harfbuzz`, `skia_enable_svg`, `skia_enable_skparagraph`, and `is_official_build=true`.
- Produce `CSkia.xcframework` (macOS arm64/x86_64, iOS, iOS simulator) and `libcskia.so` (linux x86_64/arm64) in a dedicated CI workflow. Publish them as release artifacts referenced by a SwiftPM `binaryTarget` with a checksum.
- Developers never build Skia locally unless they change `CSkia`.

## Error model

- **Bundle/lint errors** are reported before render with source locations, in a machine-readable form so an agent can fix them.
- **Unsupported style at runtime** (dynamic values that lint couldn't see) produces a warning with `data-ms-src`. The engine then ignores the property, or fails if `--strict` is set (the default in CI).
- **Asset errors** (404, decode failure, `delayRender` timeout) fail the frame and report the asset URL and source location.
