# Open-source MIT Remotion examples: Remotion vs MotionSwift (2026-11-14)

`node tests/tools/open-source-visual.mjs` on an Apple M4 Max (16 cores, 128 GB), eight workers per engine, one run without warmup. Pins: Remotion 4.0.542, Chrome for Testing 157.0.8103.39. Each composition lives under `Examples/MotionShowcase/OpenSource/` with full commit hashes and MIT license texts in `provenance.json` and `THIRD-PARTY-LICENSES.txt`.

## Still-frame visual parity (all 12 compositions)

Each composition's showcase `previewFrame` is rendered at native full resolution (`1920×1080`, or `1600×1000` for `ProductDemo`) by Chrome Remotion (`renderStill`) and by `motionswift still --backend=gpu` / `--backend=cpu`.

| Composition | Upstream MIT repo | Source | Frame | Resolution | SSIM | PSNR | Pixels > 8 levels |
|---|---|---|---:|---|---:|---:|---:|
| `DynamicIsland` | [`zz41354899/SwiftClip`](https://github.com/zz41354899/SwiftClip) | Unmodified TSX | 75 | 1920×1080 | 0.9984 | 37.07 dB | 0.08% |
| `DataGauge` | [`lifeprompt-team/remotion-scenes`](https://github.com/lifeprompt-team/remotion-scenes) | Subset-adapted | 65 | 1920×1080 | 0.9973 | 35.43 dB | 0.14% |
| `ShapeCircularProgress` | [`lifeprompt-team/remotion-scenes`](https://github.com/lifeprompt-team/remotion-scenes) | Subset-adapted | 65 | 1920×1080 | 0.9967 | 34.47 dB | 0.16% |
| `BarChartAnim` | [`RenderComp/free-remotion-templates`](https://github.com/RenderComp/free-remotion-templates) | Unmodified TSX | 90 | 1920×1080 | 0.9955 | 31.85 dB | 0.33% |
| `LowerThirdGlassCard` | [`RenderComp/free-remotion-templates`](https://github.com/RenderComp/free-remotion-templates) | Subset-adapted | 60 | 1920×1080 | 0.9945 | 34.58 dB | 0.48% |
| `BackgroundAurora` | [`lifeprompt-team/remotion-scenes`](https://github.com/lifeprompt-team/remotion-scenes) | Subset-adapted | 60 | 1920×1080 | 0.9924 | 29.48 dB | 1.54% |
| `LineChartAnim` | [`RenderComp/free-remotion-templates`](https://github.com/RenderComp/free-remotion-templates) | Subset-adapted | 115 | 1920×1080 | 0.9915 | 31.02 dB | 0.74% |
| `DataViz` | [`zz41354899/SwiftClip`](https://github.com/zz41354899/SwiftClip) | Unmodified TSX | 75 | 1920×1080 | 0.9913 | 29.31 dB | 0.45% |
| `BokehCircles` | [`RenderComp/free-remotion-templates`](https://github.com/RenderComp/free-remotion-templates) | Subset-adapted | 75 | 1920×1080 | 0.9895 | 29.30 dB | 1.91% |
| `CountdownTimer` | [`zz41354899/SwiftClip`](https://github.com/zz41354899/SwiftClip) | Unmodified TSX | 60 | 1920×1080 | 0.9859 | 26.47 dB | 0.67% |
| `MetricDashboard` | [`zz41354899/SwiftClip`](https://github.com/zz41354899/SwiftClip) | Unmodified TSX | 60 | 1920×1080 | 0.9678 | 20.98 dB | 1.69% |
| `ProductDemo` | [`Alexwtlf/agentic-product-demo`](https://github.com/Alexwtlf/agentic-product-demo) | Subset-adapted | 265 | 1600×1000 | 0.9374 | 22.15 dB | 3.11% |

Remaining pixel differences come primarily from glyph advance and default block-heading vertical spacing between Chrome Blink + CoreText and SkParagraph + CoreText (for example `MetricDashboard`'s `<h1>` margin and `ProductDemo`'s UI/monospace tracking).

## Full-resolution H.264 export speed and memory (6 featured clips)

Export times are end-to-end wall clock (process startup, TSX bundling/compilation, rendering, and H.264 encoding) with `--concurrency=8`. Peak RSS samples the full process tree every 100 ms.

| Clip | Resolution · Frames | Remotion (x264) | MotionSwift Metal + x264 | MotionSwift Metal + Shared VideoToolbox | Peak RSS (Remotion → Shared VT) |
|---|---|---:|---:|---:|---:|
| `BarChartAnim` | 1920×1080 · 150f | 19.94 s | 2.08 s (9.60×, SSIM 0.9969) | 2.04 s (9.78×, SSIM 0.9965) | 3,335 MiB → 778 MiB (−76.7%) |
| `BackgroundAurora` | 1920×1080 · 120f | 15.36 s | 1.93 s (7.94×, SSIM 0.9947) | 1.87 s (8.21×, SSIM 0.9947) | 3,457 MiB → 194 MiB (−94.4%) |
| `DynamicIsland` | 1920×1080 · 150f | 19.84 s | 2.70 s (7.35×, SSIM 0.9995) | 2.68 s (7.40×, SSIM 0.9995) | 3,401 MiB → 573 MiB (−83.1%) |
| `LowerThirdGlassCard` | 1920×1080 · 120f | 16.91 s | 2.50 s (6.77×, SSIM 0.9965) | 2.43 s (6.95×, SSIM 0.9963) | 3,547 MiB → 368 MiB (−89.6%) |
| `ShapeCircularProgress` | 1920×1080 · 90f | 13.79 s | 2.03 s (6.78×, SSIM 0.9981) | 2.09 s (6.61×, SSIM 0.9980) | 2,608 MiB → 147 MiB (−94.4%) |
| `ProductDemo` (`200-319`) | 1600×1000 · 120f | 17.64 s | 11.06 s (1.59×, SSIM 0.9548) | 11.20 s (1.58×, SSIM 0.9529) | 3,271 MiB → 554 MiB (−83.1%) |

Geometric-mean speedup across all 6 full-resolution clips: **5.87× faster** (`Metal + x264`) and **5.92× faster** (`Metal + shared IOSurface / VideoToolbox`), with **76.7%–94.4% lower peak process-tree RSS** on the shared IOSurface path. Across the five 1080p motion templates, geometric-mean speedup is **7.62×** (`Metal + x264`) and **7.71×** (`Metal + shared IOSurface / VideoToolbox`) at video SSIM **0.9947–0.9995**.

## Reproduce

```sh
make bootstrap build
node tests/tools/open-source-visual.mjs --stills-only   # 12-composition still-frame parity
node tests/tools/open-source-visual.mjs --write-docs    # full video benchmark + README assets
```
