# Video codecs and render controls

`motionswift render` validates codec, pixel format, quality, scaled dimensions and container before rendering. A one-frame encode at the requested size probes availability first. Hardware modes require hardware; missing codecs, rejected settings and inaccessible hardware fail with diagnostics. There is no automatic software fallback.

| Codec | Encoder | Pixel format | Alpha | Container |
|---|---|---|---|---|
| `h264` | `software`, `videotoolbox`, `videotoolbox-shared` | `yuv420p` | No | MP4 or MOV |
| `hevc` | `software`, `videotoolbox`, `videotoolbox-shared` | `yuv420p` | No | MP4 or MOV |
| `prores` (422 HQ) | `software` | `yuv422p10le` | No | MOV |
| `prores4444` | `software` | `yuva444p10le` | Yes | MOV |

Other combinations are rejected. ProRes hardware and HEVC alpha are outside the supported matrix. Select software ProRes explicitly; requesting hardware ProRes fails. The shared path requires `--backend=gpu` and accepts IOSurface-backed BGRA input. Pixel-format names describe the encoder conversion target; the renderer currently supplies 8-bit RGBA/BGRA, so 10-bit ProRes does not add source precision. Decoded ProRes 4444 may be reported as `yuva444p12le` by FFmpeg.

`--quality=N` uses native codec units: software H.264/HEVC CRF 0–51, default 18; ProRes quantizer 1–31, default 9; VideoToolbox quality 0–100, default 65. Lower is better for software, higher is better for VideoToolbox. These values do not imply equivalent quality across codecs.

```sh
.build/release/motionswift render --project tests --entry perf/codec-fixture.tsx \
  CodecFixture /tmp/alpha.mov --codec=prores4444 --pixel-format=yuva444p10le --quality=9

.build/release/motionswift render --project tests --entry perf/long.tsx \
  Layers /tmp/segments.mp4 --codec=hevc --encoder=videotoolbox-shared --backend=gpu \
  --segments=60-119,0-29 --frame-step=2 --report-json=/tmp/segments.json
```

`--frames=a-b` selects an inclusive range. `--segments=a-b,c-d` selects inclusive ranges in the given order, including repeats; the two options are mutually exclusive. `--frame-step=N` samples each segment starting at its first frame. Output fps is source fps divided by N. Every selected frame has equal duration; a final incomplete step is rounded up to one output frame. Segment timestamps start at zero and concatenation produces a continuous timeline. Frame reordering is disabled to make packet boundaries predictable. Determinism means frame order and timeline, not byte-identical container files.

Each segment is independently encoded with identical settings, then concatenated by FFmpeg stream copy. Temporary files live beside the destination and are removed on failure or handled SIGINT/SIGTERM. Only completed output is atomically renamed over the destination. SIGKILL and system crashes cannot run cleanup. Reports expose availability, encode-write/backpressure, encode-finish, concat/publish and combined wall times; worker rendering overlaps encoding. Quality, codec, pixel format, step, output fps and segment count are included in `stages`.

## Verification and regression gate

Run `MOTIONSWIFT_TEST_HARDWARE=1 swift test --no-parallel` and `node tests/tools/codec-cli.mjs` after a release build. Fixtures verify codec metadata, dimensions, frame count, fps, decoded color/alpha, stepped segment boundaries, unsupported settings, unavailable encoder diagnostics and SIGTERM cleanup. Hardware tests require working hardware and fail when it is unavailable.

The push-only **Codec regression gate** workflow runs these fixtures plus `node tests/perf/codecs.mjs`. The codec matrix gate is enabled by default: it checks 30/300-frame 720p Layers exports against measured wall-time and sampled process-tree RSS budgets in `tests/perf/codec-budgets.json`. Missing memory, unavailable hardware, failed decode/metadata and exceeded budgets fail. Budgets use 50% headroom over the initial measured median time and peak RSS and require the same CPU model. Other hosts must establish their own budgets with `--measure-only`; that flag deliberately does not enforce limits. It is not used by CI.

See [the measured snapshot](benchmarks/2026-11-13-codecs.md). This gate covers the codec matrix; the older full Remotion benchmark's informational policy is unchanged. Process-tree RSS excludes separately measured GPU/media-engine allocations and may double-count shared pages.
