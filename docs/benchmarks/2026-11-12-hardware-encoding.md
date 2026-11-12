# Hardware H.264 encoding benchmark (2026-11-12)

Local measurements of the implementation in this PR, based on `6e4fdbb`. The working tree contained the new encoder paths during measurement; the base SHA in raw reports is not a claim that main already had these paths.

Machine: Apple M4 Max, 16 cores, 128 GB; darwin 27.2.0 (arm64); Node v22.19.0.
FFmpeg: `ffmpeg version 8.1 Copyright (c) 2000-2026 the FFmpeg developers`.

One warmup + three measured runs per cell, eight render workers. Times include startup, rendering, and finished-file encoding. Native modes ran sequentially. Local SSIM reference is CPU + x264; Remotion was not rerun locally. CI runs Remotion on the short 180p/720p tiers. All 24 fixture/resolution cases passed exact frame-count/dimension/fps checks and SSIM >= 0.98 for all three alternative pipelines.

Software uses x264 CRF 18/medium. FFmpeg VideoToolbox uses quality 65 with software fallback disabled. Shared IOSurface uses native AVFoundation/VideoToolbox quality 0.65 with hardware required. These are different quality controls; file sizes are included below rather than assuming equivalent compression.

The shared path keeps F16 drawing, resolves to BGRA8 on the GPU, synchronizes completion, and passes an IOSurface-backed CVPixelBuffer to the native encoder. It removes application CPU pixel readback and ffmpeg pipe transport. Encoder color conversion and internal copies may still occur.

## Aggregate speedups over Metal + x264

| Clips | Resolution | FFmpeg VideoToolbox | Shared IOSurface VideoToolbox | Cases |
|---|---|---:|---:|---:|
| 30 frames | 180p | 0.83x | 0.98x | 6 |
| 30 frames | 720p | 0.82x | 0.96x | 6 |
| 30 frames | 4k | 0.99x | 1.12x | 6 |
| 300 frames | 720p | 0.92x | 1.02x | 3 |
| 300 frames | 4k | 1.03x | 1.07x | 3 |

Geometric means; above 1x is faster. Gains are modest for these synthetic scenes, and hardware paths do not consistently help small clips. Software remains the default. For 300-frame clips, shared IOSurface averages 1.41x over CPU + x264 across both resolutions.

## 30-frame clips

| Fixture | CPU + x264 (s) | Metal + x264 (s) | FFmpeg VT (s) | Shared VT (s) | Shared vs Metal + x264 | Shared SSIM |
|---|---:|---:|---:|---:|---:|---:|
| core/solid@180p | 0.400 | 0.437 | 0.517 | 0.448 | 0.98x | 0.999996 |
| core/boxes@180p | 0.394 | 0.433 | 0.520 | 0.440 | 0.98x | 0.998674 |
| motion/translate@180p | 0.399 | 0.437 | 0.528 | 0.446 | 0.98x | 0.998924 |
| core/flex@180p | 0.394 | 0.430 | 0.533 | 0.450 | 0.96x | 0.998607 |
| core/opacity@180p | 0.402 | 0.433 | 0.523 | 0.443 | 0.98x | 0.998885 |
| motion/sequence-spring@180p | 0.397 | 0.441 | 0.531 | 0.448 | 0.98x | 0.998302 |
| core/solid@720p | 0.410 | 0.442 | 0.537 | 0.477 | 0.93x | 0.999996 |
| core/boxes@720p | 0.436 | 0.444 | 0.552 | 0.457 | 0.97x | 0.999449 |
| motion/translate@720p | 0.428 | 0.449 | 0.556 | 0.458 | 0.98x | 0.999616 |
| core/flex@720p | 0.438 | 0.442 | 0.538 | 0.459 | 0.96x | 0.999506 |
| core/opacity@720p | 0.434 | 0.441 | 0.535 | 0.472 | 0.93x | 0.999682 |
| motion/sequence-spring@720p | 0.420 | 0.452 | 0.556 | 0.454 | 1.00x | 0.999538 |
| core/solid@4k | 0.825 | 0.765 | 0.802 | 0.703 | 1.09x | 0.999996 |
| core/boxes@4k | 0.918 | 0.786 | 0.798 | 0.710 | 1.11x | 0.999813 |
| motion/translate@4k | 0.901 | 0.767 | 0.805 | 0.713 | 1.08x | 0.999882 |
| core/flex@4k | 0.976 | 0.776 | 0.800 | 0.704 | 1.10x | 0.999832 |
| core/opacity@4k | 0.873 | 0.775 | 0.806 | 0.733 | 1.06x | 0.999890 |
| motion/sequence-spring@4k | 0.963 | 0.896 | 0.807 | 0.683 | 1.31x | 0.999847 |

<details><summary>Measured runs (ms) and final output sizes (bytes)</summary>

| Fixture / engine | Three measured runs (ms) | Output bytes |
|---|---|---:|
| core/solid@180p / cpu | 396.01, 399.74, 399.74 | 2444 |
| core/solid@180p / gpu | 432.34, 439.52, 437.46 | 2444 |
| core/solid@180p / gpu-hw | 522.57, 516.88, 513.63 | 1565 |
| core/solid@180p / gpu-shared | 448.03, 453.06, 437.51 | 1716 |
| core/boxes@180p / cpu | 393.99, 397.18, 391.64 | 3061 |
| core/boxes@180p / gpu | 433.20, 431.04, 435.18 | 3075 |
| core/boxes@180p / gpu-hw | 514.73, 520.79, 520.18 | 2924 |
| core/boxes@180p / gpu-shared | 439.83, 439.08, 448.27 | 2564 |
| motion/translate@180p / cpu | 399.29, 393.27, 404.01 | 4783 |
| motion/translate@180p / gpu | 431.06, 436.80, 443.70 | 4783 |
| motion/translate@180p / gpu-hw | 524.67, 528.08, 530.65 | 4052 |
| motion/translate@180p / gpu-shared | 456.90, 446.31, 441.32 | 4527 |
| core/flex@180p / cpu | 392.51, 393.73, 396.42 | 2672 |
| core/flex@180p / gpu | 433.11, 428.98, 429.57 | 2672 |
| core/flex@180p / gpu-hw | 522.69, 532.70, 534.80 | 2096 |
| core/flex@180p / gpu-shared | 444.90, 458.59, 449.60 | 2068 |
| core/opacity@180p / cpu | 397.47, 404.42, 401.51 | 2772 |
| core/opacity@180p / gpu | 437.43, 433.44, 425.06 | 2772 |
| core/opacity@180p / gpu-hw | 524.77, 520.99, 523.44 | 2516 |
| core/opacity@180p / gpu-shared | 441.66, 445.73, 442.93 | 2341 |
| motion/sequence-spring@180p / cpu | 397.41, 395.23, 398.69 | 4543 |
| motion/sequence-spring@180p / gpu | 446.61, 440.97, 437.32 | 4543 |
| motion/sequence-spring@180p / gpu-hw | 533.44, 530.95, 530.09 | 3342 |
| motion/sequence-spring@180p / gpu-shared | 447.87, 462.81, 446.86 | 3654 |
| core/solid@720p / cpu | 409.68, 407.02, 415.84 | 3283 |
| core/solid@720p / gpu | 441.68, 443.42, 435.04 | 3283 |
| core/solid@720p / gpu-hw | 537.09, 529.59, 542.79 | 2648 |
| core/solid@720p / gpu-shared | 477.23, 490.35, 468.63 | 2668 |
| core/boxes@720p / cpu | 438.05, 435.91, 421.43 | 5317 |
| core/boxes@720p / gpu | 443.69, 438.99, 452.63 | 5320 |
| core/boxes@720p / gpu-hw | 546.03, 551.94, 558.99 | 6539 |
| core/boxes@720p / gpu-shared | 451.39, 456.61, 460.87 | 4901 |
| motion/translate@720p / cpu | 425.74, 428.35, 428.30 | 6917 |
| motion/translate@720p / gpu | 440.07, 449.25, 450.58 | 6917 |
| motion/translate@720p / gpu-hw | 555.86, 551.22, 565.95 | 5758 |
| motion/translate@720p / gpu-shared | 457.84, 464.55, 453.03 | 6592 |
| core/flex@720p / cpu | 445.43, 436.02, 438.40 | 3822 |
| core/flex@720p / gpu | 445.05, 442.08, 436.16 | 3822 |
| core/flex@720p / gpu-hw | 537.55, 534.87, 554.92 | 3215 |
| core/flex@720p / gpu-shared | 456.38, 459.27, 466.88 | 2943 |
| core/opacity@720p / cpu | 435.98, 433.05, 433.81 | 3569 |
| core/opacity@720p / gpu | 451.82, 440.07, 441.14 | 3569 |
| core/opacity@720p / gpu-hw | 535.02, 533.32, 539.75 | 3125 |
| core/opacity@720p / gpu-shared | 452.74, 472.00, 475.27 | 2985 |
| motion/sequence-spring@720p / cpu | 419.79, 419.83, 424.02 | 7284 |
| motion/sequence-spring@720p / gpu | 452.36, 451.17, 1448.07 | 7284 |
| motion/sequence-spring@720p / gpu-hw | 548.29, 556.01, 569.96 | 5460 |
| motion/sequence-spring@720p / gpu-shared | 459.67, 450.45, 453.61 | 5977 |
| core/solid@4k / cpu | 824.57, 833.87, 818.78 | 10428 |
| core/solid@4k / gpu | 761.94, 766.58, 765.27 | 10428 |
| core/solid@4k / gpu-hw | 793.36, 802.36, 806.39 | 12116 |
| core/solid@4k / gpu-shared | 734.36, 697.94, 703.49 | 10970 |
| core/boxes@4k / cpu | 917.90, 893.74, 973.97 | 15264 |
| core/boxes@4k / gpu | 786.47, 785.22, 787.22 | 15233 |
| core/boxes@4k / gpu-hw | 797.91, 796.26, 803.65 | 20405 |
| core/boxes@4k / gpu-shared | 686.75, 709.56, 721.07 | 16455 |
| motion/translate@4k / cpu | 901.34, 845.38, 938.89 | 17121 |
| motion/translate@4k / gpu | 776.19, 761.51, 766.54 | 17121 |
| motion/translate@4k / gpu-hw | 804.70, 796.84, 819.41 | 17862 |
| motion/translate@4k / gpu-shared | 712.86, 715.49, 707.29 | 19928 |
| core/flex@4k / cpu | 975.98, 982.48, 974.64 | 10967 |
| core/flex@4k / gpu | 790.20, 775.65, 772.46 | 10967 |
| core/flex@4k / gpu-hw | 799.64, 795.38, 805.77 | 12488 |
| core/flex@4k / gpu-shared | 708.39, 704.39, 687.24 | 11204 |
| core/opacity@4k / cpu | 872.72, 881.84, 866.97 | 10626 |
| core/opacity@4k / gpu | 774.33, 783.71, 775.15 | 10626 |
| core/opacity@4k / gpu-hw | 809.38, 806.03, 802.77 | 12350 |
| core/opacity@4k / gpu-shared | 731.14, 739.03, 732.67 | 11104 |
| motion/sequence-spring@4k / cpu | 965.99, 959.47, 963.22 | 20085 |
| motion/sequence-spring@4k / gpu | 896.29, 894.81, 900.33 | 20085 |
| motion/sequence-spring@4k / gpu-hw | 806.96, 806.68, 806.75 | 16302 |
| motion/sequence-spring@4k / gpu-shared | 683.11, 684.12, 682.37 | 17787 |

</details>

## 300-frame clips

| Fixture | CPU + x264 (s) | Metal + x264 (s) | FFmpeg VT (s) | Shared VT (s) | Shared vs Metal + x264 | Shared SSIM |
|---|---:|---:|---:|---:|---:|---:|
| long/flex@720p | 1.192 | 1.057 | 1.162 | 1.050 | 1.01x | 0.999504 |
| long/opacity@720p | 1.131 | 1.036 | 1.136 | 1.023 | 1.01x | 0.999683 |
| long/sequence-spring@720p | 1.077 | 1.075 | 1.142 | 1.043 | 1.03x | 0.999517 |
| long/flex@4k | 5.012 | 2.663 | 2.997 | 2.900 | 0.92x | 0.999831 |
| long/opacity@4k | 5.245 | 2.983 | 3.009 | 2.878 | 1.04x | 0.999891 |
| long/sequence-spring@4k | 5.633 | 3.749 | 3.026 | 2.877 | 1.30x | 0.999839 |

<details><summary>Measured runs (ms) and final output sizes (bytes)</summary>

| Fixture / engine | Three measured runs (ms) | Output bytes |
|---|---|---:|
| long/flex@720p / cpu | 1191.88, 1191.30, 1205.81 | 21037 |
| long/flex@720p / gpu | 1063.47, 1056.67, 1029.28 | 21037 |
| long/flex@720p / gpu-hw | 1121.60, 1162.23, 1176.32 | 22512 |
| long/flex@720p / gpu-shared | 1051.41, 1049.74, 1045.93 | 19431 |
| long/opacity@720p / cpu | 1131.34, 1128.97, 1144.36 | 20482 |
| long/opacity@720p / gpu | 1035.81, 1023.29, 1059.17 | 20482 |
| long/opacity@720p / gpu-hw | 1141.47, 1135.77, 1123.46 | 21762 |
| long/opacity@720p / gpu-shared | 1013.42, 1038.66, 1022.76 | 19376 |
| long/sequence-spring@720p / cpu | 1076.42, 1084.16, 1077.09 | 59065 |
| long/sequence-spring@720p / gpu | 1055.99, 1074.89, 1098.08 | 59065 |
| long/sequence-spring@720p / gpu-hw | 1142.12, 1154.40, 1129.80 | 46082 |
| long/sequence-spring@720p / gpu-shared | 1042.89, 1035.98, 1050.39 | 51301 |
| long/flex@4k / cpu | 5352.76, 4954.13, 5011.99 | 83579 |
| long/flex@4k / gpu | 2746.47, 2663.44, 2641.31 | 83579 |
| long/flex@4k / gpu-hw | 2987.47, 3009.18, 2997.19 | 109837 |
| long/flex@4k / gpu-shared | 2903.51, 2899.78, 2879.87 | 92089 |
| long/opacity@4k / cpu | 5244.51, 5228.38, 5288.47 | 84003 |
| long/opacity@4k / gpu | 3082.21, 2945.47, 2982.71 | 84003 |
| long/opacity@4k / gpu-hw | 3013.75, 2981.70, 3008.76 | 108687 |
| long/opacity@4k / gpu-shared | 2885.24, 2872.25, 2878.43 | 91044 |
| long/sequence-spring@4k / cpu | 5826.71, 5632.98, 5470.01 | 192444 |
| long/sequence-spring@4k / gpu | 3774.13, 3749.27, 3476.83 | 192444 |
| long/sequence-spring@4k / gpu-hw | 3026.48, 2997.46, 3987.89 | 149257 |
| long/sequence-spring@4k / gpu-shared | 2876.83, 2887.31, 2876.26 | 160193 |

</details>

## Reproduce

```sh
MOTIONSWIFT_TEST_HARDWARE=1 make test
make visual
node tests/perf/bench.mjs --engines cpu,gpu,gpu-hw,gpu-shared --out tests/reports/bench
node tests/perf/bench.mjs --config tests/perf/bench.long.config.json --out tests/reports/bench/long
node tests/perf/combine-summaries.mjs
```

Raw local JSON and logs: `tests/reports/bench/` and `tests/reports/bench/long/`. CI uploads both as the `bench-results` artifact and posts both comparison tables on the PR.
