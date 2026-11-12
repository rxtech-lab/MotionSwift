# Benchmark: Remotion vs native CPU vs native GPU (runs on every PR)

> The Phase 0 benchmark is implemented. See [the current contract](current-implementation.md#benchmark-and-runner-setup) for the active fixtures, exact runner labels, browser pin, API worker, and limitations. The extended CLI/output schema below remains the target.

## Hardware encoding comparison

See the [local hardware-encoding benchmark snapshot](benchmarks/2026-11-12-hardware-encoding.md) for measured short- and long-clip results, quality checks, output sizes, and raw run timings.

The active benchmark includes `gpu-hw` (Metal + FFmpeg VideoToolbox) and `gpu-shared` (Metal → shared IOSurface → native AVFoundation/VideoToolbox) alongside `cpu` (CPU + x264), `gpu` (Metal + x264), and Remotion. Every native command explicitly selects its encoder, so the existing `gpu` result continues to isolate rendering speed and both CLI render backends retain their software default.

VideoToolbox uses `h264_videotoolbox -allow_sw 0 -q:v 65 -realtime 0`; software remains x264 CRF 18/medium. Hardware encoding uses Apple's media engine and fails if unavailable; it does not fall back to software. These quality scales are different. All speedups require the same SSIM >= 0.98 and metadata checks. Output byte sizes and FFmpeg version are included in `results.json` to expose compression tradeoffs. The FFmpeg hardware path retains GPU readback, CPU pixel conversion, and pipe transport. The shared path performs F16-to-BGRA8 conversion on the GPU, synchronizes completion, and passes the IOSurface-backed pixel buffer directly to native hardware encoding at quality 0.65. Encoder color conversion and internal copies may still occur.

The PR table compares both hardware paths against Metal + x264 and compares shared IOSurface transport against FFmpeg VideoToolbox. It includes per-resolution speedups and quality checks. Short clips have 30 frames; a second native-only matrix has 300-frame clips at 720p and 4K. Run the native matrix locally with:

```sh
node tests/perf/bench.mjs --engines cpu,gpu,gpu-hw,gpu-shared
node tests/perf/bench.mjs --config tests/perf/bench.long.config.json --out tests/reports/bench/long
```

`--encoder=software|videotoolbox|videotoolbox-shared` selects the CLI video encoder independently of `--backend`. Both render backends and the library `VideoStream` initializer default to software. The shared encoder requires `--backend=gpu`. Hardware tests run in CI and can be enabled locally with `MOTIONSWIFT_TEST_HARDWARE=1 make test`.

Every pull request gets a benchmark comment that compares Remotion's render time with MotionSwift's Skia CPU and Skia Metal (GPU) backends for the same compositions, at several output resolutions. This doc specifies the script, its config, its output, and the CI workflow. They are built in Phase 0 ([implementation-plan.md](implementation-plan.md)). See [performance.md](performance.md) for the performance model and budgets.

## Files (planned)

| Path | Purpose |
|---|---|
| `tests/perf/bench.mjs` | Benchmark script. Uses only Node built-ins, no npm dependencies. Runs with Node ≥ 20. |
| `tests/perf/bench.config.json` | The fixtures to benchmark and the run settings. |
| `.github/workflows/benchmark.yml` | Runs the script and posts the PR comment. |
| `tests/reports/bench/` | Output: `results.json`, `summary.md`, and `logs/` (gitignored). |

## What the script does

For each resolution tier and each fixture in the config:

1. **Remotion:** run `npx --no-install remotion render <entry> <comp> <out.mp4> --codec=h264 --overwrite --log=verbose [--concurrency] [--frames] [--props]` from the fixture project `tests/compositions/`.
2. **Native:** run the same render through `motionswift` once per backend, `--backend=cpu` and `--backend=gpu`, with the tier's `--scale` (CLI contract below). The Remotion driver passes the same `scale` to `renderMedia()`.
3. Repeat each engine `warmup + runs` times. Record wall time with `process.hrtime`, including startup, because that's what users wait for. Discard the warm-up runs.
4. Count frames with `ffprobe -count_packets` and compute fps = frames / median wall time.
5. **Parity:** compute SSIM between each native video and the reference (`ffmpeg -lavfi "[0:v][1:v]ssim"`). The reference is Remotion, or the CPU backend for tiers that do not run Remotion. A speedup counts only if SSIM ≥ `minSsim`, because fast but wrong doesn't count.
6. **Baseline:** if `--baseline <results.json>` (schema 2, from the latest `main` run) is given, compute the CPU and GPU median deltas per fixture. A slowdown larger than `--regression-threshold` (default 15%) is flagged as a regression.
7. Write `results.json` and `summary.md`, and save every run's full log under `logs/`.

**Graceful degradation:**

| Situation | Behavior |
|---|---|
| `tests/compositions/package.json` doesn't exist yet | Write a "skipped" summary and exit 0. |
| No native binary (before the engine exists) | Native is shown as `unavailable`. Remotion is still measured, which gives the Phase 0 baseline. |
| A render fails | That cell shows ❌ with a link to its log. The other fixtures still run, and the script exits 1 at the end. |

Native binary lookup order: `--native-bin`, then `$MOTIONSWIFT_BIN`, then `.build/release/motionswift`, then `motionswift` on `PATH`. A candidate is accepted if `--version` exits 0.

### Script options

| Flag | Default | Meaning |
|---|---|---|
| `--config` | `tests/perf/bench.config.json` | Fixtures, tiers and settings |
| `--out` | `tests/reports/bench` | Report directory |
| `--work-dir` | OS temp dir | Rendered videos go here, so they stay out of the artifact |
| `--runs` / `--warmup` | from config (3 / 1) | Measured and warm-up runs |
| `--only` | all | Comma-separated fixture ids |
| `--tiers` | all | Comma-separated tier ids, for example `4k` |
| `--engines` | `remotion,cpu,gpu` | Subset of engines, for example `cpu,gpu` for local profiling. `native` is an alias for `cpu`. |
| `--concurrency` | from config | One number for every engine. The config may set a per-engine object. |
| `--baseline` | none | `results.json` from `main` |
| `--regression-threshold` | `0.15` | Relative slowdown that counts as a regression |
| `--fail-on-regression` | off | Exit 1 on regression. Turned on after Phase 5. |

Exit codes: `0` ok, `1` a render failed (or a regression with `--fail-on-regression`), `2` the script crashed.

### Native CLI contract

The engine's CLI must accept this. It's frozen here so the benchmark and the engine can be built separately.

```text
motionswift --version
motionswift render --project <dir> --entry <file> <composition> <out.mp4>
                   --codec=h264 [--backend=cpu|gpu] [--concurrency=N|auto] [--scale=N]
                   [--frames=a-b] [--props=<file.json>] --report-json <file>
```

`--report-json` writes per-stage timings, which the script copies into `results.json` when present:

```jsonc
// Implemented today
{ "backend": "skia-metal", "workers": 8, "scale": 12, "frames": 30,
  "encoder": "ffmpeg-libx264-rawvideo-pipe", "startupMs": 255,
  "stages": { "frameMs": {"p50": 22.1, "p95": 27.0}, "renderAndEncodeMs": 445 } }
// Target: finer stages
{ "stages": { "jsMs": {"p50": 0.8, "p95": 1.6}, "applyOpsMs": {...}, "layoutMs": {...},
              "recordMs": {...}, "rasterMs": {...}, "encodeWaitMs": {...} } }
```

`frameMs` is one worker's evaluate + layout + raster + readback time per frame. `renderAndEncodeMs` is the wall time from the first frame to the finished file, with rendering and encoding overlapped.

## Config: `bench.config.json`

```jsonc
{
  "project": "../compositions",      // relative to the config file
  "entryPoint": "src/index.ts",
  "codec": "h264",
  "runs": 3,
  "warmup": 1,
  "minSsim": 0.98,                    // both sides are lossy H.264, so this is looser than the stills thresholds
  "concurrency": {"remotion": 8, "cpu": 8, "gpu": 8},   // or one number for all engines
  "tiers": [                          // output resolution = composition size × scale
    {"id": "180p", "scale": 1,  "engines": ["remotion", "cpu", "gpu"]},
    {"id": "720p", "scale": 4,  "engines": ["remotion", "cpu", "gpu"]},
    {"id": "4k",   "scale": 12, "engines": ["cpu", "gpu"]}  // Remotion's scale >= 5 times out in the pinned Chrome
  ],
  "fixtures": [
    { "id": "core/text-shapes",             "composition": "BenchTextShapes",   "frames": "0-149" },
    { "id": "effects/blur-shadow-gradient", "composition": "BenchEffects",      "frames": "0-149" },
    { "id": "media/offthread-video",        "composition": "BenchVideoInVideo", "frames": "0-149" },
    { "id": "core/4k-output",               "composition": "Bench4K",           "frames": "0-59" },
    { "id": "real/short-clip",              "composition": "RealShortClip",     "props": { } }
  ]
}
```

The fixtures match the composition types in the README's throughput table, so measured numbers can replace the estimates there. Keep the PR benchmark under about 15 minutes by limiting long fixtures with `frames`.

## Output

### `results.json` (schema 2)

```jsonc
{
  "schema": 2,
  "createdAt": "2026-11-12T10:00:00Z",
  "git": { "sha": "…", "ref": "feature/x" },
  "machine": { "platform": "darwin 25.0 (arm64)", "cpu": "Apple M2", "cores": 8, "memoryGB": 16, "runner": "…", "node": "v22…" },
  "settings": { "runs": 3, "warmup": 1, "codec": "h264", "concurrency": {"remotion": 8, "cpu": 8, "gpu": 8},
                "minSsim": 0.98, "tiers": [...], "regressionThreshold": 0.15 },
  "versions": { "remotion": "4.0.x", "native": "motionswift 0.2.0-phase0" },
  "fixtures": [{
    "id": "core/opacity@720p", "fixture": "core/opacity", "tier": "720p", "scale": 4,
    "composition": "Layers", "frames": "0-29",
    "remotion": { "status": "ok", "runsMs": [...], "medianMs": 9400, "stdevMs": 80, "frames": 30, "fps": 3.2, "logFile": "logs/…" },
    "cpu":      { "status": "ok", "runsMs": [...], "medianMs": 430, "stdevMs": 10, "frames": 30, "fps": 70, "stages": {...} },
    "gpu":      { "status": "ok", "runsMs": [...], "medianMs": 420, "stdevMs": 10, "frames": 30, "fps": 71, "stages": {...} },
    "parity":   { "cpu": {"reference": "remotion", "ssim": 0.9994, "result": "pass"},
                  "gpu": {"reference": "remotion", "ssim": 0.9994, "result": "pass"} },
    "speedups": { "cpuVsRemotion": 21.9, "gpuVsRemotion": 22.4, "gpuVsCpu": 1.02 },
    "baseline": { "cpu": {"medianMs": 425, "deltaPct": 0.01, "regression": false}, "gpu": {...} }
  }],
  "totals": { "gpuVsCpu": {"geomean": 1.3, "fixtures": 18}, "gpuVsRemotion": {...}, "cpuVsRemotion": {...},
              "gpuVsCpu@180p": {...}, "gpuVsCpu@720p": {...}, "gpuVsCpu@4k": {...} }
}
```

`status` is one of `ok`, `failed`, or `unavailable`. The headline numbers are the **geometric-mean speedups** (GPU vs CPU, GPU vs Remotion, CPU vs Remotion) over fixtures that passed parity. GPU vs CPU is also reported per tier.

### `summary.md` (the PR comment)

It starts with the hidden marker `<!-- motionswift-bench -->`, which the workflow uses to find and update its own comment:

```markdown
## MotionSwift benchmark: Remotion vs native CPU vs native GPU

- **GPU vs CPU** (native Skia Metal vs Skia raster): **1.30×** geometric mean over 18 fixture(s); by resolution: 180p 1.00×, 720p 1.05×, 4k 1.40×.
- **GPU vs Remotion**: **20.10×** over 12 fixture(s) with output parity.
- **CPU vs Remotion**: **19.80×** over 12 fixture(s) with output parity.

| Fixture | Size | Remotion | Native CPU | Native GPU | GPU vs CPU | GPU vs Remotion | CPU vs Remotion | Frame p50 ms CPU / GPU | SSIM CPU / GPU | GPU vs main |
|---|---|---|---|---|---|---|---|---|---|---|
| core/opacity@720p | 1280×720 | 9.40 s (3 fps) | 0.43 s (70 fps) | 0.42 s (71 fps) | **1.02×** | 22.38× | 21.86× | 22.0 / 17.0 | 0.9994 ✅ / 0.9994 ✅ | +1.0% |
| core/opacity@4k | 3840×2160 | — | 0.93 s (32 fps) | 0.70 s (43 fps) | **1.33×** | — | — | 80.0 / 30.0 | — / 1.0000 ✅ | — |

<details><summary>Environment and raw runs</summary> … commit, machine, versions, every run time, stdev … </details>

Full logs and `results.json`: workflow run → artifact `bench-results`.
```

Markers: ✅/❌ for SSIM parity, 🔺 on a GPU regression against `main`, and — for an engine that does not run in that tier. The numbers above are illustrative.

## CI workflow: `benchmark.yml`

**Triggers:** `push` only, on all branches. Pull-request and manual events do not start benchmark or test runs.
**Permissions:** `contents: read`, `pull-requests: write`, `actions: read`.
**Concurrency:** one run per branch. A new push cancels the previous run.
**Runner:** `[self-hosted, macOS, ARM64]`. The table always shows the machine, so results from different machines aren't compared by mistake.

Steps:

| # | Step | Notes |
|---|---|---|
| 1 | Checkout, set up Node LTS and stable Rust | Shared `.github/actions/setup` action. |
| 2 | Install missing native tools | Homebrew supplies SwiftLint, pkg-config, and ffmpeg/ffprobe when missing; verify all prerequisites. |
| 3 | Install fixtures and pinned browser | `make bootstrap` installs `tests/` dependencies, the pinned Chrome, and the native archive. |
| 4 | Build native | `make build`. |
| 5 | Download baseline (branches other than main) | `gh run list --workflow benchmark.yml --branch main --event push --status success --limit 1`, then `gh run download <id> --name bench-results` into a run-specific directory in `$RUNNER_TEMP`. `continue-on-error`. |
| 6 | Run benchmark | `node tests/perf/bench.mjs --work-dir $RUNNER_TEMP/bench [--baseline …]` |
| 7 | Job summary | `if: always()`: append `summary.md` to `$GITHUB_STEP_SUMMARY`. |
| 8 | Upload artifact | `if: always()`: upload `tests/reports/bench/` as `bench-results` (30-day retention). `main` runs become the next baseline. |
| 9 | Post or update the PR comment | On non-cancelled branch runs, find an open same-repository PR associated with the pushed SHA and branch. Update the bot's marked comment or create it. Skip commenting if there is no matching current PR. |

**Fork PR events** do not start these workflows. Golden regeneration remains a separate manual workflow.

**Gating:** the benchmark is informational. It fails only if a render fails, until Phase 5. After Phase 5, `--fail-on-regression` is enabled and the job becomes a required check.

## Running locally

```text
node tests/perf/bench.mjs --only core/text-shapes --runs 5
node tests/perf/bench.mjs --engines cpu,gpu --tiers 4k --native-bin .build/release/motionswift
```

Output appears in `tests/reports/bench/summary.md`.
