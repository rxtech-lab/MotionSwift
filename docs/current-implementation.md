# Runnable implementation

The repository now contains a **macOS Phase 0 package**, not the complete multi-platform engine described by the design documents. `docs/implementation-plan.md` remains the roadmap. The following is the implemented contract.

## Build and commands

Required: macOS on Apple Silicon, Xcode/Swift 6, Rust via rustup, Node 22, SwiftLint 0.65.1, ffmpeg/ffprobe, pkg-config, and Git LFS. Local verification used Swift 6.4.2, Rust 1.91.1, and SwiftLint 0.65.1. The native library is pinned to rust-skia 0.99.0; Yoga is pinned to 3.2.1 in SwiftPM. npm dependencies and their transitive versions are pinned in `tests/package-lock.json`.

```sh
make bootstrap                  # npm ci, pinned browser, native Skia archive, pkg-config
make lint                       # SwiftLint, strict warnings, error at 800 lines
make build                      # optimized Swift executable
make test                       # Swift and Node/TypeScript tests
make visual                     # compare native stills with committed Remotion goldens
make benchmark                  # measured videos from both engines, results + Markdown
make ci                         # lint, build, tests, visual comparisons
```

All test dependencies are installed in `tests/node_modules`. Production JS packages live under `js/`. Visual composition sources live in `tests/compositions/visuals/`; the same fixture manifest supplies the benchmark. Reference PNGs live in `tests/golden/stills/` with generator, browser, source and file hashes in `tests/golden/metadata.json`. Reports go to the gitignored `tests/reports/` folder.

`make native` configures the system library through `native/pkgconfig/motionswift-skia.pc`. To invoke SwiftPM directly after bootstrap, set `PKG_CONFIG_PATH="$PWD/native/pkgconfig"`. A changed native archive invalidates the Swift build, so an incremental build cannot silently use an old static library. The bootstrap downloads prebuilt Skia through rust-skia's binary cache when available; it is not yet an independently published XCFramework.

```sh
.build/release/motionswift list --project tests/compositions --entry src/index.ts
.build/release/motionswift check --project tests/compositions --entry src/index.ts
.build/release/motionswift still --project tests/compositions --entry src/index.ts Boxes /tmp/boxes.png --frame=15
.build/release/motionswift render --project tests/compositions --entry src/index.ts Motion /tmp/motion.mp4 \
  --codec=h264 --concurrency=1 --frames=0-29 --report-json /tmp/stages.json
```

`--props=<file.json>`, `--dump-layout=<file.json>`, and `--backend=cpu` are supported. Unknown flags, invalid frame ranges, unsupported codecs/backends/concurrency, and unsupported runtime style values fail. A copied CLI needs `MOTIONSWIFT_HOME` pointing to this checkout and its installed test toolchain.

## What runs

- SwiftPM modules: MotionCore, MotionCompiler, MotionRuntime, MotionLayout, SkiaKit, MotionRender, MotionEncode, and the CLI.
- SWC strips TS/TSX, including enums, namespaces, and `satisfies`, and transforms JSX/CommonJS. A closed graph includes local imports, JSON, pinned React, the shim, the actual React reconciler, and Scheduler. Disallowed packages fail resolution. This spike uses SWC's Node binding; the portable Rust compiler C ABI is still planned.
- `check` invokes TypeScript against the subset declarations, runs compiler subset diagnostics, enumerates compositions, and validates a frame through the native painter. Errors from TypeScript have rule/file/line/column/message fields. Other compiler/runtime errors go to stderr with a nonzero exit status. It does not yet honor project tsconfig aliases or emit source maps/stamps.
- React 18 and react-reconciler 0.29 run inside **JavaScriptCore**, not Node. Native render trees cross the bridge as JSON snapshots. Each frame gets a fresh VM for frame-order independence; retained mutation buffers and incremental subtree caches are still planned.
- `AbsoluteFill`, `Composition`, `Still`, `Folder`, `registerRoot`, frame/config hooks, `interpolate`, basic `Easing`, `spring` with physical configuration, `Sequence`, `Freeze`, and `Loop` run. Spring duration/reverse/delay options and the rest of Remotion's APIs are not exposed.
- Yoga computes flex layout, absolute/relative positioning, sizing, min/max sizes, percent/px lengths, margins, padding, gap, alignment, wrapping, basis/grow/shrink, and aspect ratio. Paint supports solid colors, rectangles, rounded corners, high-precision opacity groups, rectangular overflow clipping, and 2D translate/rotate/scale around the center. Colors currently accept hex plus transparent/black/white/red/green/blue. Unsupported styles fail instead of falling back silently.
- Low-level Skia text drawing exists, but paragraph measurement/wrapping are not implemented and the painter explicitly rejects text nodes. Do not interpret the shape-fixture results as text support.
- Video rendering produces a private PNG sequence and encodes silent H.264/yuv420p with ffmpeg/libx264. Hardware encoding, audio, image/video decoding, GPU rendering, and zero-copy output are still planned.
- Native tests execute SWC → JSC, verify frame independence, compare JSC spring samples to Remotion traces, and exercise the actual Skia PNG writer. Node tests cover pixel gate boundaries, interpolation/spring parity, benchmark statistics, and valid/rejected TypeScript fixtures.

## Visual gate

Every push and same-repository PR triggers `.github/workflows/output-check.yml` on `[self-hosted, macOS, ARM64]`. There are no path filters. Fork code is not executed on the self-hosted runner.

The comparator checks **every RGBA channel exactly**. A pixel counts as different if any channel differs, including alpha and anti-aliasing. The test fails when more than **0.003 of all pixels (0.3%)** differ; exactly 0.3% passes. Dimensions must match. There is no per-fixture relaxation, ignored anti-aliasing region, or known-issue exemption. Each frame is rendered twice to require bit-identical native repeatability. Sampling uses a shuffled order and fresh frame VMs.

References come only from real Remotion and the pinned stock Chrome for Testing in `tests/browser.lock.json`. This avoids a root-loading timeout observed locally with Remotion's patched headless shell and keeps the reference raster backend consistent. `make goldens` or the manual regeneration workflow is the explicit update path. CI comparison never regenerates references. Changed fixture sources, manifest, browser pin, Remotion version, or PNG hashes fail provenance validation before comparison. Reference generation must use the same macOS ARM64 platform as the runner.

`visual-results` contains expected/actual/diff PNGs, metrics, and a side-by-side HTML report. The manual golden workflow uploads candidates for review; it does not publish or commit them automatically.

## Benchmark and runner setup

Register an Apple Silicon Mac with the repository and labels `self-hosted`, `macOS`, and `ARM64`. Install the prerequisites above. Both workflows use that runner with no GitHub-hosted fallback. This checkout initially has no remote; a repository must be configured and these files published before a remote run can be dispatched.

The benchmark runs on every push, same-repository PR, and manual dispatch. It uses the six shared shape/motion fixtures, three measured runs and one warmup per engine, with concurrency one. These are small synthetic compositions, not anonymized Film Studio projects or a representative 1080p workload.

Each Remotion measurement launches a fresh Node worker that bundles the TSX, opens the pinned browser, and calls the real `renderMedia()` API. Each native measurement launches the CLI. Both encoders use H.264, CRF 18, the medium x264 preset and yuv420p. Both wall times include startup; browser installation happens during bootstrap. Videos are checked with ffprobe for codec, dimensions, fps and exact frame count, then ffmpeg SSIM (minimum 0.98). Only fixtures passing video parity enter the geometric-mean speedup. PNG parity is checked independently by the output workflow.

Each same-repository PR gets one updated comment marked `<!-- motionswift-bench -->`. Push runs store results; successful `main` artifacts become PR baselines. Deltas are omitted when the physical runner/hardware, Node, browser, fixture sources, or render settings differ. The benchmark records failures and logs, and is informational for speed regressions unless `--fail-on-regression` is requested. A failed render or failed parity check returns nonzero.

```sh
node tests/perf/bench.mjs --runs 1 --warmup 0
node tests/perf/bench.mjs --only core/solid --runs 5 --warmup 1
node tests/perf/bench.mjs --engines native --native-bin .build/release/motionswift
```

Not implemented yet: the portable swc C ABI/module cache/source maps, incremental retained bridge, full CSS/text/effects/SVG/media, motion/layout trace CLI, video audio checks, published binary/npm distributions, SwiftUI MotionStudio/editor operations, iOS compilation/runtime packaging, Linux JSC/GPU backends, and production cloud worker. The existing design documents describe these next phases rather than current capabilities.
