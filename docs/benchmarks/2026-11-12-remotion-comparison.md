# Remotion rendering comparison (2026-11-12)

Recorded local run: `2026-11-12T12:20:59.933Z`, Apple M4 Max, 16 cores, 128 GB, darwin 27.2.0 arm64. Remotion 4.0.542, Chrome for Testing 157.0.8103.39, MotionSwift 0.2.0-phase0, FFmpeg 8.1, Node v22.19.0. Eight workers per engine, one measured run, no warmup, 30 frames per case. Wall-clock times include startup, compilation/bundling, rendering and H.264 encoding, with process-tree RSS sampled approximately every 100 ms.

Remotion and native software paths use x264 CRF 18/medium. The shared IOSurface path uses native VideoToolbox quality 0.65; these quality controls are not equivalent. All cases below passed frame-count, resolution, FPS and SSIM ≥ 0.98 checks against Remotion. This is a short synthetic workload comparison, not full-film throughput or exact pixel parity. Remotion was not measured at 4K.

## Export time in seconds

| Fixture | Remotion | MotionSwift CPU + x264 | MotionSwift Metal + x264 | MotionSwift Metal + shared IOSurface / VideoToolbox |
|---|---:|---:|---:|---:|
| core/solid@180p | 10.847 | 0.386 | 0.414 | 0.476 |
| core/boxes@180p | 5.444 | 0.382 | 0.464 | 0.444 |
| motion/translate@180p | 5.497 | 0.384 | 0.454 | 0.447 |
| core/flex@180p | 5.494 | 0.382 | 0.415 | 0.448 |
| core/opacity@180p | 5.416 | 0.384 | 0.454 | 0.447 |
| motion/sequence-spring@180p | 5.468 | 0.378 | 0.421 | 0.448 |
| core/solid@720p | 9.127 | 0.396 | 0.444 | 0.462 |
| core/boxes@720p | 9.248 | 0.409 | 0.421 | 0.459 |
| motion/translate@720p | 8.588 | 0.418 | 0.421 | 0.459 |
| core/flex@720p | 9.584 | 0.421 | 0.418 | 0.458 |
| core/opacity@720p | 9.235 | 0.411 | 0.445 | 0.457 |
| motion/sequence-spring@720p | 9.145 | 0.408 | 0.444 | 0.455 |

Geometric-mean speedups over these 12 cases, calculated from unrounded times: CPU + x264 **18.89×**, Metal + x264 **17.24×**.

For `core/boxes@720p`, shared IOSurface export took 0.459 s versus Remotion's 9.248 s (**20.15× faster**); peak sampled process-tree RSS was 255.5 MiB versus 2,520.2 MiB (**89.9% lower**). Shared output SSIM was 0.999118. RSS excludes separate GPU/media-engine accounting, can double-count shared pages, and can miss short peaks. See the [memory snapshot](2026-11-12-memory.md) for every fixture's peak.

## Reproduce

```sh
node tests/perf/bench.mjs --runs 1 --warmup 0 --allow-unavailable-hardware --out tests/reports/bench/memory-short
```

This snapshot preserves the timing values from the local `tests/reports/bench/memory-short/results.json` report (a gitignored output). Fresh measurements depend on the checkout, machine and installed tools.
