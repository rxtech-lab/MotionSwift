# Benchmark: Remotion vs native (runs on every PR)

> The Phase 0 benchmark is implemented. See [the current contract](current-implementation.md#benchmark-and-runner-setup) for the active fixtures, exact runner labels, browser pin, API worker, and limitations. The extended CLI/output schema below remains the target.

Every pull request gets a benchmark comment that compares Remotion's render time with MotionSwift's for the same compositions. This doc specifies the script, its config, its output, and the CI workflow. They are built in Phase 0 ([implementation-plan.md](implementation-plan.md)). See [performance.md](performance.md) for the performance model and budgets.

## Files (planned)

| Path | Purpose |
|---|---|
| `tests/perf/bench.mjs` | Benchmark script. Uses only Node built-ins, no npm dependencies. Runs with Node ≥ 20. |
| `tests/perf/bench.config.json` | The fixtures to benchmark and the run settings. |
| `.github/workflows/benchmark.yml` | Runs the script and posts the PR comment. |
| `tests/reports/bench/` | Output: `results.json`, `summary.md`, and `logs/` (gitignored). |

## What the script does

For each fixture in the config:

1. **Remotion:** run `npx --no-install remotion render <entry> <comp> <out.mp4> --codec=h264 --overwrite --log=verbose [--concurrency] [--frames] [--props]` from the fixture project `tests/compositions/`.
2. **Native:** run the same render through `motionswift` (CLI contract below).
3. Repeat each engine `warmup + runs` times. Record wall time with `process.hrtime`, including startup, because that's what users wait for. Discard the warm-up runs.
4. Count frames with `ffprobe -count_packets` and compute fps = frames / median wall time.
5. **Parity:** compute SSIM between the two output videos (`ffmpeg -lavfi "[0:v][1:v]ssim"`). A speedup counts only if SSIM ≥ `minSsim`, because fast but wrong doesn't count.
6. **Baseline:** if `--baseline <results.json>` (from the latest `main` run) is given, compute the native median delta per fixture. A slowdown larger than `--regression-threshold` (default 15%) is flagged as a regression.
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
| `--config` | `tests/perf/bench.config.json` | Fixture list |
| `--out` | `tests/reports/bench` | Report directory |
| `--work-dir` | OS temp dir | Rendered videos go here, so they stay out of the artifact |
| `--runs` / `--warmup` | from config (3 / 1) | Measured and warm-up runs |
| `--only` | all | Comma-separated fixture ids |
| `--engines` | `remotion,native` | Run just one side, for example for local profiling |
| `--concurrency` | engine default | Passed to both engines |
| `--baseline` | none | `results.json` from `main` |
| `--regression-threshold` | `0.15` | Relative slowdown that counts as a regression |
| `--fail-on-regression` | off | Exit 1 on regression. Turned on after Phase 5. |

Exit codes: `0` ok, `1` a render failed (or a regression with `--fail-on-regression`), `2` the script crashed.

### Native CLI contract

The engine's CLI must accept this. It's frozen here so the benchmark and the engine can be built separately.

```text
motionswift --version
motionswift render --project <dir> --entry <file> <composition> <out.mp4>
                   --codec=h264 [--concurrency=N] [--frames=a-b] [--props=<file.json>]
                   --report-json <file>
```

`--report-json` writes per-stage timings, which the script copies into `results.json` when present:

```jsonc
{ "stages": { "jsMs": {"p50": 0.8, "p95": 1.6}, "applyOpsMs": {...}, "layoutMs": {...},
              "recordMs": {...}, "rasterMs": {...}, "encodeWaitMs": {...} },
  "startupMs": 210 }
```

## Config: `bench.config.json`

```jsonc
{
  "project": "../compositions",      // relative to the config file
  "entryPoint": "src/index.ts",
  "codec": "h264",
  "runs": 3,
  "warmup": 1,
  "minSsim": 0.98,                    // both sides are lossy H.264, so this is looser than the stills thresholds
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

### `results.json` (schema 1)

```jsonc
{
  "schema": 1,
  "createdAt": "2026-11-12T10:00:00Z",
  "git": { "sha": "…", "ref": "feature/x" },
  "machine": { "platform": "darwin 25.0 (arm64)", "cpu": "Apple M2", "cores": 8, "memoryGB": 16, "runner": "…", "node": "v22…" },
  "settings": { "runs": 3, "warmup": 1, "codec": "h264", "concurrency": null, "minSsim": 0.98, "regressionThreshold": 0.15 },
  "versions": { "remotion": "4.0.x", "native": "motionswift 0.1.0" },
  "fixtures": [{
    "id": "core/text-shapes", "composition": "BenchTextShapes", "frames": "0-149",
    "remotion": { "status": "ok", "runsMs": [...], "medianMs": 5200, "stdevMs": 80, "frames": 150, "fps": 28.8, "logFile": "logs/…" },
    "native":   { "status": "ok", "runsMs": [...], "medianMs": 520, "stdevMs": 10, "frames": 150, "fps": 288, "stages": {...} },
    "speedup": 10.0, "ssim": 0.993, "parity": "pass",
    "baseline": { "nativeMedianMs": 500, "deltaPct": 0.04, "regression": false }
  }],
  "totals": { "comparable": 4, "geomeanSpeedup": 8.3 }
}
```

`status` is one of `ok`, `failed`, or `unavailable`. The headline number is the **geometric-mean speedup** over fixtures that passed parity.

### `summary.md` (the PR comment)

It starts with the hidden marker `<!-- motionswift-bench -->`, which the workflow uses to find and update its own comment:

```markdown
## 🏁 MotionSwift benchmark: Remotion vs native

**Geometric-mean speedup: 8.30×** across 4 fixture(s) with output parity.

| Fixture | Frames | Remotion (median) | Native (median) | Speedup | SSIM | Native vs `main` |
|---|---:|---:|---:|---:|---:|---:|
| `core/text-shapes` | 150 | 5.20 s (28.8 fps) | 0.52 s (288.5 fps) | 10.00× | 0.9930 ✅ | +4.0% |
| `media/offthread-video` | 150 | 12.10 s (12.4 fps) | 1.80 s (83.3 fps) | 6.72× | 0.9850 ✅ | −2.1% |
| `core/4k-output` | 60 | 11.00 s (5.5 fps) | ❌ failed | — | — | — |

<details><summary>Environment and raw runs</summary> … commit, machine, versions, every run time, stdev … </details>

Full logs and `results.json`: workflow run → artifact `bench-results`.
```

Markers: ✅/❌ for SSIM parity, ⚠️ on a speedup whose parity failed, 🔺 on a regression against `main`, and ⚪ when native is unavailable.

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
node tests/perf/bench.mjs --engines native --native-bin .build/release/motionswift
```

Output appears in `tests/reports/bench/summary.md`.
