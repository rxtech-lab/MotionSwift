# Performance model and measurement

The numbers in the [README](../README.md#speed-estimates) are **estimates**. This document explains where they come from and how we turn them into measurements.

The model below describes the target architecture. The current implementation uses Skia Ganesh and defaults to x264. FFmpeg VideoToolbox is opt-in; a separate native IOSurface/VideoToolbox path removes application CPU pixel readback and pipe transport. GPU resolve, synchronization, and encoder color conversion remain. Retained-tree caching is not implemented. See [the current implementation](current-implementation.md) and [encoder benchmark comparison](benchmark.md#hardware-encoding-comparison).

## Why native is faster

1. **No screenshot round trip.** Remotion asks Chrome for a screenshot (PNG/JPEG encode), copies it over the DevTools protocol, and decodes it again for ffmpeg. That costs 10–40 ms per frame and grows with pixel count. MotionSwift keeps the frame on the GPU from raster to encoder (IOSurface → CVPixelBuffer → VideoToolbox).
2. **Incremental work.** A retained tree with dirty flags means unchanged subtrees reuse their recorded `SkPicture`, and layout runs only when a layout property changes.
3. **No browser startup.** A JSContext with the bundle loaded starts in under 300 ms, compared with 2–5 s to launch a browser and load the bundle.
4. **Hardware encode and decode.** VideoToolbox (or NVENC/VAAPI) instead of software ffmpeg for both `OffthreadVideo` decoding and output encoding.

## Benchmark protocol

The benchmark script (`tests/perf/bench.mjs`) renders the same fixtures with both engines and posts the comparison as a comment on every PR. Its full specification is in [benchmark.md](benchmark.md). These rules apply to it and to any manual benchmark.

| Item | Rule |
|---|---|
| Hardware | Record the exact machine (chip, cores, RAM, OS). Benchmarks from different machines are never compared. |
| Remotion baseline | Pinned Remotion version, `npx remotion render --log=verbose`, default concurrency, `--image-format=jpeg` (the Remotion default). Record the per-stage timing from the verbose log. |
| MotionSwift | `motionswift render … --report-json <file>` ([CLI contract](benchmark.md#native-cli-contract)). Reports per-stage percentiles (p50/p95) for JS, apply ops, layout, record, raster, and encode wait. |
| Runs | 1 warm-up plus 3 measured runs on PRs, or 5 for release benchmarks. Report the median wall time and fps. |
| Output parity | A benchmark result is valid only if SSIM between the two output videos is at or above `minSsim`. Fast but wrong doesn't count. |

## Budgets (regression gates once implemented)

| Metric | Budget (M-series, 1080p30) |
|---|---|
| Cold start to first frame | ≤ 300 ms |
| Scrub frame (preview, text/shape) | ≤ 8 ms |
| Steady-state text/shape render | ≥ 200 fps whole machine |
| JS per frame (macOS, JIT) | ≤ 2 ms p95 |
| Peak memory per worker | ≤ 300 MB, excluding video decode surfaces |

CI tracks these numbers through the PR benchmark ([benchmark.md](benchmark.md)), ideally on a self-hosted Apple Silicon runner. From Phase 5 on, a native slowdown of more than 15% compared with the latest `main` run fails the check.

## Known slow paths

- `backdrop-filter` and large `filter: blur()` radii need offscreen layers. Cache them when the content underneath is static.
- Text with many fallback fonts triggers font collection lookups. Prewarm them at load.
- `OffthreadVideo` with seeks backwards is slow. Each worker gets a contiguous range, so decoding stays mostly sequential.
- The WebKit fallback costs about as much as Remotion (1–2×). Show its use in render reports so the cost is visible.
