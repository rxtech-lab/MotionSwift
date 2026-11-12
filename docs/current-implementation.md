# Runnable implementation

The repository now contains a **macOS Phase 0 package**, not the complete multi-platform engine described by the design documents. `docs/implementation-plan.md` remains the roadmap. The following is the implemented contract.

## Build and commands

Required: macOS on Apple Silicon, Xcode/Swift 6, Rust via rustup, Node 22, SwiftLint 0.65.1, ffmpeg/ffprobe, pkg-config, and Git LFS. Local verification used Swift 6.4.2, Rust 1.91.1, and SwiftLint 0.65.1. The native library is pinned to rust-skia 0.99.0 with the `metal`, `textlayout`, `svg`, and `webp` features; this combination has an official prebuilt Apple Silicon archive. Yoga is pinned to 3.2.1 in SwiftPM. npm dependencies and their transitive versions are pinned in `tests/package-lock.json`.

```sh
make bootstrap                  # npm ci, pinned browser, native Skia archive, pkg-config
make lint                       # SwiftLint, strict warnings, error at 800 lines
make build                      # optimized Swift executable
make test                       # Swift and Node/TypeScript tests
make visual                     # compare CPU and GPU native stills with committed Remotion goldens
make benchmark                  # Remotion vs native CPU vs native GPU videos, results + Markdown
make ci                         # lint, build, tests, visual comparisons
```

All test dependencies are installed in `tests/node_modules`. Production JS packages live under `js/`. Visual composition sources live in `tests/compositions/visuals/`; the same fixture manifest supplies the benchmark. Reference PNGs live in `tests/golden/stills/` with generator, browser, source and file hashes in `tests/golden/metadata.json`. Reports go to the gitignored `tests/reports/` folder.

`make native` configures the system library through `native/pkgconfig/motionswift-skia.pc`. To invoke SwiftPM directly after bootstrap, set `PKG_CONFIG_PATH="$PWD/native/pkgconfig"`. A changed native archive invalidates the Swift build, so an incremental build cannot silently use an old static library. The bootstrap downloads prebuilt Skia through rust-skia's binary cache when available; it is not yet an independently published XCFramework.

```sh
.build/release/motionswift list --project tests/compositions --entry src/index.ts
.build/release/motionswift check --project tests/compositions --entry src/index.ts
.build/release/motionswift still --project tests/compositions --entry src/index.ts Boxes /tmp/boxes.png --frame=15
.build/release/motionswift render --project tests/compositions --entry src/index.ts Motion /tmp/motion.mp4 \
  --codec=h264 --backend=gpu --concurrency=8 --scale=6 --frames=0-29 --report-json /tmp/stages.json
.build/release/motionswift render --project tests/compositions --entry src/index.ts Motion /tmp/shared.mp4 \
  --backend=gpu --encoder=videotoolbox-shared --scale=6 --report-json /tmp/shared-stages.json
```

`--props=<file.json>` and `--dump-layout=<file.json>` are supported. Other render options:

| Option | Default | Meaning |
|---|---|---|
| `--backend=cpu\|gpu` | `cpu` | Skia raster, or Skia Ganesh on Metal. Both pass the same 0.3% golden gate. |
| `--encoder=software\|videotoolbox\|videotoolbox-shared` | `software` | x264 CRF 18/medium, FFmpeg hardware H.264 quality 65, or native IOSurface hardware H.264 quality 0.65 (requires GPU). Hardware modes fail if unavailable. |
| `--concurrency=N\|auto` | `auto` (half the cores) | Frame-render worker threads for `render`. |
| `--scale=N` | `1` | Output pixels per composition pixel, like Remotion's `scale`. Layout stays in CSS pixels. |

Unknown flags, invalid frame ranges, unsupported codecs or backends, non-positive concurrency or scale, and unsupported runtime style values fail. A copied CLI needs `MOTIONSWIFT_HOME` pointing to this checkout and its installed test toolchain.

## What runs

- SwiftPM modules: MotionCore, MotionCompiler, MotionRuntime, MotionLayout, SkiaKit, MotionRender, MotionEncode, and the CLI.
- SWC strips TS/TSX, including enums, namespaces, and `satisfies`, and transforms JSX/CommonJS. A closed graph includes local imports, JSON, pinned React, the shim, the actual React reconciler, and Scheduler. Disallowed packages fail resolution. This spike uses SWC's Node binding; the portable Rust compiler C ABI is still planned.
- `check` invokes TypeScript against the subset declarations, runs compiler subset diagnostics, enumerates compositions, and validates a frame through the native painter. Errors from TypeScript have rule/file/line/column/message fields. Other compiler/runtime errors go to stderr with a nonzero exit status. It does not yet honor project tsconfig aliases or emit source maps/stamps.
- React 18 and react-reconciler 0.29 run inside **JavaScriptCore**, not Node. Native render trees cross the bridge as JSON snapshots. Each frame gets a fresh VM for frame-order independence; retained mutation buffers and incremental subtree caches are still planned.
- `AbsoluteFill`, `Composition`, `Still`, `Folder`, `registerRoot`, frame/config hooks, `interpolate`, basic `Easing`, `spring` with physical configuration, `Sequence`, `Freeze`, and `Loop` run. Spring duration/reverse/delay options and the rest of Remotion's APIs are not exposed.
- Yoga computes flex layout, absolute/relative positioning, sizing, min/max sizes, percent/px lengths, margins, padding, gap, alignment, wrapping, basis/grow/shrink, and aspect ratio. Paint supports solid colors, rectangles, rounded corners, high-precision opacity groups, rectangular overflow clipping, and 2D translate/rotate/scale around the center. Colors currently accept hex plus transparent/black/white/red/green/blue. Unsupported styles fail instead of falling back silently.
- Low-level Skia text drawing exists, but paragraph measurement/wrapping are not implemented and the painter explicitly rejects HTML text nodes. SVG data-URI `img` nodes with explicit dimensions and `objectFit: 'contain'` now render through Skia's SVG DOM on CPU or Metal. Plain SVG text runs receive explicit letter spacing and CoreText font fallback spans before Skia rendering. Direct inline SVG host nodes, remote images, and raster image decoding remain unsupported. This limited SVG image path does not establish general text/CSS support or Chrome pixel parity. The local real-clip workflow and saved WebP comparison artifacts are documented in [the Test Film fixture](../tests/fixtures/test-film/README.md).
- `render` runs a parallel frame pipeline (`MotionRender/FramePipeline.swift`). Each worker thread owns a JavaScriptCore runtime and a Skia surface. GPU workers also own a Metal command queue and Ganesh context. Nothing mutable is shared between workers. Finished frames pass through a bounded reorder window, so memory stays bounded at 4K. They are then streamed in order as raw unpremultiplied RGBA into one ffmpeg process, which encodes silent H.264/yuv420p while later frames render. CPU and GPU default to libx264. `--encoder=videotoolbox` selects FFmpeg hardware encoding with hardware required (`-allow_sw 0`). No PNG sequence is written. Raw rendered pixels match between worker counts and, on the current fixtures, CPU/GPU backends; the two lossy encoders need not produce identical video bytes.
- The GPU backend renders into a half-float Metal target and converts to 8 bits once, at readback. Ganesh normally sends constant paint colors as premultiplied byte vertex colors (color × coverage 81.5 → 82), so the GPU path supplies fractional quad coverage through a float-uniform SkSL shader and layer opacity through a color-matrix filter. Opaque layers become plain saves on the GPU. Without these steps, edges and opacity groups drift by one channel value from the raster pipeline and the Remotion goldens.
- `--backend=gpu --encoder=videotoolbox-shared` resolves the F16 Skia surface to an IOSurface-backed BGRA8 Metal texture, synchronizes GPU completion, and hands its shared `CVPixelBuffer` to native AVFoundation/VideoToolbox with hardware required. There is no application CPU pixel readback, `Data` frame allocation, or ffmpeg pipe. A GPU conversion pass and encoder RGB-to-YUV conversion remain; this is shared-buffer transport, not a guarantee that Apple's encoder makes no internal copies. Each worker owns a pixel-buffer pool and texture cache; retained frame buffers are independent and the ordered pipeline plus encoder readiness provide backpressure. Audio and image/video decoding remain planned. H.264 output requires even pixel dimensions. Hardware quality 0.65/65 is not equivalent to x264 CRF 18; benchmark parity is checked rather than assumed.
- Native tests execute SWC → JSC, verify frame independence, compare JSC spring samples to Remotion traces, and exercise the actual Skia PNG writer. They also check CPU/GPU pixel equality, render scale, in-order delivery from the parallel pipeline (matching serial output on both backends), and propagation of worker and consumer errors. Node tests cover pixel gate boundaries, interpolation/spring parity, benchmark statistics, and valid/rejected TypeScript fixtures.
- Hardware-enabled tests encode and decode real videos through FFmpeg VideoToolbox and native IOSurface output, verify decoded frame order/colors, compare shared GPU RGB against readback including transparency, and retain shared frames beyond worker shutdown to exercise CoreVideo cache lifetime.
- CI first probes a real hardware-only H.264 session at the fixture resolution. Known session-availability failures are reported in the job summary and disable only hardware encoder tests; this is skipped coverage, not successful hardware validation. Swift tests run serially to avoid concurrent cold Metal shader compilations and competing hardware sessions. GPU rendering/parity tests still run. Hardware encoder tests use the probe's 320×180 dimensions.

## Visual gate

Only pushes trigger `.github/workflows/output-check.yml` on `[self-hosted, macOS, ARM64]`. There are no path filters or duplicate pull-request runs. Fork PR events do not execute code on the self-hosted runner.

The comparator checks **every RGBA channel exactly**. A pixel counts as different if any channel differs, including alpha and anti-aliasing. The test fails when more than **0.003 of all pixels (0.3%)** differ; exactly 0.3% passes. Dimensions must match. There is no per-fixture relaxation, ignored anti-aliasing region, or known-issue exemption. `make visual` runs the suite once per backend (`node tests/tools/visual.mjs --backend=cpu|gpu`), with reports under `tests/reports/visual/<backend>/`. Each frame is rendered twice to require bit-identical native repeatability. Sampling uses a shuffled order and fresh frame VMs.

References come only from real Remotion and the pinned stock Chrome for Testing in `tests/browser.lock.json`. This avoids a root-loading timeout observed locally with Remotion's patched headless shell and keeps the reference raster backend consistent. `make goldens` or the manual regeneration workflow is the explicit update path. CI comparison never regenerates references. Changed fixture sources, manifest, browser pin, Remotion version, or PNG hashes fail provenance validation before comparison. Reference generation must use the same macOS ARM64 platform as the runner.

`visual-results` contains expected/actual/diff PNGs, metrics, and a side-by-side HTML report. The manual golden workflow uploads candidates for review; it does not publish or commit them automatically.

Push CI additionally runs the [Test Film still regression](../tests/fixtures/test-film/README.md#ci-visual-regression): 16 fresh Remotion/native CPU frame pairs, checked against OS-pinned exact native RGBA hashes with repeatability and reviewed lossless Remotion WebP goldens (at most 0.3% changed pixels, maximum one-unit channel delta). This catches new differences without claiming the real clip passes cross-engine pixel parity. Reviewed reference WebPs, hashes, metadata, and the 14.1 KB source project ZIP are committed. CI verifies and extracts that archive into a temporary directory, runs the check, and removes the source afterward. The runner needs no Desktop fixture or cloud credentials; changed archive or source hashes fail the check. PNG comparisons/diffs and an HTML review are uploaded under `visual-results/test-film`, with results in the job summary. Full-length videos and animated WebPs remain a local verification workflow.

## Benchmark and runner setup

Register an Apple Silicon Mac with the repository and labels `self-hosted`, `macOS`, and `ARM64`. Provide Xcode/Swift, Homebrew, and Git LFS. The shared `.github/actions/setup` action selects the current Node LTS, installs stable Rust via rustup, installs missing SwiftLint, pkg-config, and ffmpeg tools through Homebrew, and verifies prerequisites before building. Actions using Node 24 require runner 2.327.1 or newer; the initial remote run used 2.338.2. Both workflows use that runner with no GitHub-hosted fallback.

The benchmark runs when a pull request is opened, synchronized, or reopened. Golden regeneration remains a separate manual workflow. It measures five combinations: Remotion, CPU + x264 (`cpu`), Metal + x264 (`gpu`), Metal + FFmpeg VideoToolbox (`gpu-hw`), and Metal + shared IOSurface/native VideoToolbox (`gpu-shared`). It uses the six shared shape/motion fixtures at three resolution tiers, with three measured runs and one warmup per engine:

| Tier | `scale` | Size | Engines | Parity reference |
|---|---|---|---|---|
| `180p` | 1 | 320×180 | Remotion, CPU, GPU, GPU-HW, Shared | Remotion |
| `720p` | 4 | 1280×720 | Remotion, CPU, GPU, GPU-HW, Shared | Remotion |
| `4k` | 12 | 3840×2160 | CPU, GPU, GPU-HW, Shared | CPU (gated by the goldens) |

Remotion and all native combinations request 8 workers, capped to the runner's available CPU cores using Node's `availableParallelism()` (or CPU count on older Node). Reports record both requested and effective per-engine counts; baseline comparisons require matching effective counts. With the pinned Chrome for Testing, Remotion's `scale` ≥ 5 times out while loading the root component, so the 4K tier compares native paths only. These are short, small synthetic compositions, not anonymized Film Studio projects. Startup, fresh JS evaluation per frame, readback, and encoding can limit end-to-end gains. Frame p50 includes JS, layout, raster, and readback; it does not isolate GPU raster time.

Each Remotion measurement launches a fresh Node worker that bundles the TSX, opens the pinned browser, and calls the real `renderMedia()` API with the tier's `scale`. Each native measurement explicitly selects `--backend`, `--encoder`, `--concurrency` and `--scale`, and verifies the reported encoder. Software uses H.264 CRF 18/medium; hardware uses H.264 quality 65 with software fallback disabled. All output is yuv420p. Wall times include startup; browser installation happens during bootstrap. Videos are checked with ffprobe for codec, dimensions, fps and exact frame count, then ffmpeg SSIM (minimum 0.98). Only fixtures passing video parity enter a geometric-mean speedup. The summary isolates hardware-vs-software encoding with identical Metal rendering and reports the combined gain over CPU + x264. Raw reports include output bytes and FFmpeg version. A second native-only matrix (`bench.long.config.json`) uses 300-frame clips at 720p and 4K to distinguish short-clip overhead from sustained throughput. Its separate entry lives outside the golden fixture project and is hashed into benchmark settings. PNG parity is checked independently by the output workflow.

PR runs store results and update one comment marked `<!-- motionswift-bench -->` through the dedicated comment job. Compatible historical successful `main` artifacts are used as branch baselines when available. Deltas are omitted when the physical runner/hardware, Node, browser, fixture sources, or render settings differ. The benchmark records failures and logs, and is informational for speed regressions unless `--fail-on-regression` is requested. A failed render or failed parity check returns nonzero.

The same workflow also benchmarks the actual bundled Test Film project with `node tests/perf/test-film.mjs --allow-unavailable-hardware`. It verifies/extracts the committed ZIP outside the artifact tree and renders all 2,700 frames of the first 90 seconds at 1920×1080/30 fps through the same five engine combinations, using pinned software Chrome. This is one measured run per engine with no warmup. Per-engine wall times include startup, compilation/bundling, rendering, and encoding; ZIP extraction and SSIM analysis are outside the timer. Full-video metadata and SSIM checks gate speedups. The real-project table appears first in the PR comment, before the synthetic tables, and its JSON/logs live under `bench-results/test-film/`. Temporary source and videos are removed. The job has a 90-minute timeout for the combined synthetic and 90-second real-project benchmarks. Local integration smoke tests can use `--frames=0-2 --engines=remotion,cpu,gpu`; CI always uses the full range.

CI benchmarks pass `--allow-unavailable-hardware`: if the independent FFmpeg hardware-only session probe reports a known availability error, hardware cells explicitly show `unavailable` with the probe diagnostics and contribute no speedups. No software fallback is enabled. Unexpected probe errors and failures after a successful probe remain failures. Local benchmark runs are strict unless this option is explicitly supplied.

```sh
node tests/perf/bench.mjs --runs 1 --warmup 0
node tests/perf/bench.mjs --only core/solid --runs 5 --warmup 1
node tests/perf/bench.mjs --engines cpu,gpu,gpu-hw,gpu-shared --tiers 4k --native-bin .build/release/motionswift
```

Phase 0 gate status on real content: **no-go**. See [phase0-validation.md](phase0-validation.md). None of the 15 real Film Studio compositions pass `motionswift check`; text, inline SVG, borders, shadows, filters and gradients are the main blockers. Remotion baselines live in `tests/perf/baseline/film-studio.json`, and the anonymized census in `tests/compositions/real/manifest.json` (`node tests/tools/real-fixtures.mjs`).

Not implemented yet: the portable swc C ABI/module cache/source maps, incremental retained bridge, full CSS/text/effects/SVG/media, motion/layout trace CLI, video audio checks, published binary/npm distributions, SwiftUI MotionStudio/editor operations, iOS compilation/runtime packaging, Linux JSC and non-Metal GPU backends, and production cloud worker. The existing design documents describe these next phases rather than current capabilities.
