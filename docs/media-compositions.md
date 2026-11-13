# Nested clips and media

Open **Media Composition** from the gallery or sidebar in `make showcase` for a 24-second master composition containing two
instances of the twelve-second media montage plus image and video compositions. The montage
itself contains nested image/video compositions and a music bed. Hover a nested composition to
see its outline; double-click it on the canvas or its clip in the timeline to open it. Timeline
labels also support double-click, and clip context menus and accessibility actions expose
**Open Composition**.

Opening a child pauses playback and maps the parent playhead to the instance's local frame,
clamped to its duration. The child's own preview, controls and timeline replace the parent's.
Use Back or any ancestor breadcrumb to return, restoring that parent's saved playhead. Repeated
instances retain their own offsets, so opening montage B subtracts its 360-frame start. Clip
placement, timeline ranges and navigation targets share the same metadata used to build the TSX.
This composition navigation is currently demonstrated in the showcase's bundled media project.

Play/pause, mute, frame stepping and scrubbing use the selected composition's clock.
Drag the triangle handle or vertical playhead line to scrub across all tracks. The line has a
24-point grab area, keeps its initial grab offset, and clamps at the first and last frame. You
can also click/drag the time ruler or a track to scrub; playback pauses while scrubbing.
**Export Composition** opens a dedicated sheet and exports the selected composition with its
mixed audio. Set `MOTIONSWIFT_SHOWCASE_START=media` to open this example first. The bundled
sources are synthetic FFmpeg test patterns and sine waves; they need no downloads.

```tsx
import {AbsoluteFill, Audio, Img, OffthreadVideo, Sequence} from 'remotion';

const SmallClip = () => <AbsoluteFill>
  <OffthreadVideo src="/absolute/path/shot.mp4" trimBefore={30} durationInFrames={90}
    volume={0.5} style={{width: '100%', height: '100%', objectFit: 'cover'}} />
</AbsoluteFill>;

export const Film = () => <AbsoluteFill>
  <Audio src="/absolute/path/music.m4a" volume={0.3} />
  <Img src="/absolute/path/poster.png" style={{width: 320, height: 180}} />
  <Sequence from={60} durationInFrames={90} layout="none">
    <div style={{position: 'absolute', left: 400, top: 100, width: 320, height: 180}}>
      <Sequence from={0} durationInFrames={90}><SmallClip /></Sequence>
    </div>
  </Sequence>
</AbsoluteFill>;
```

`Sequence` gives each child a local frame; offsets add through nested sequences. Reuse a React
component inside different sequences for independent smaller clips. A `Composition` registers a
catalog entry; render its component, rather than nesting registration elements inside a film.
Children keep the parent composition's fps and `useVideoConfig()` dimensions. Explicitly size
containers when placing a smaller clip; use `overflow: 'hidden'` to clip its content.

## Supported media contract

- `Img` and raw `img`: PNG/JPEG and other ImageIO raster formats, using absolute local paths,
  file URLs or data URIs. SVG data URIs retain the Skia SVG path. Specify width and height.
  Raster images support `contain`, `cover` and `fill`. Stage remote images locally first.
- `OffthreadVideo` / `Video`: native AVFoundation frame extraction for formats supported by the
  host OS, with preferred orientation applied. Absolute paths, file URLs and HTTP(S) asset URLs
  are accepted. Local staged assets give reproducible offline renders. Frames beyond the source
  duration are transparent. Videos may carry audio; `muted` silences it.
- `Audio`: native AVPlayer preview; exported audio is decoded with FFmpeg and mixed into stereo
  48 kHz AAC. Both audio and video support numeric `volume` or a local-frame callback in [0, 1],
  positive `playbackRate`, `trimBefore`/`trimAfter`, the aliases `startFrom`/`endAt`, and source
  `durationInFrames`. Trim values are measured at the composition fps; the end is exclusive.
  Source seconds are `(trimBefore + localFrame * playbackRate) / fps`.
- `Freeze` freezes the picture and silences its media; `Loop` repeats media time. Sequence exits,
  selection changes and pause stop preview voices. Audio preview follows delivered picture frames
  with drift correction; it is not a sample-accurate audio-master playback engine.

`FramePipeline` delivers evaluated media samples in `RenderedFrame.media`. Library exporters
should append these to `AudioMix` at the output fps and call `mux(video:)` after their video
stream finishes. The macOS CLI and showcase export do this automatically, including range/frame
step exports. Multi-segment CLI exports mix the selected frames in output order and encode audio once
after joining their picture segments, preserving silent gaps without per-segment AAC priming.

Current limits: no `staticFile()` asset-root resolution, browser media events, streaming/HLS
contract, GIF animation, arbitrary codec guarantees, or `useAudioData`/waveform helpers. Raster
images are cached with a 64 MiB cost limit per worker and video generators are bounded per worker.
Video decoding and raster uploads copy pixels; the shape-only shared-surface performance claims
should not be applied to media-heavy compositions. Offline playback-rate conversion resamples
audio and changes pitch. Export uses memory-mapped decoded PCM scratch files and requires
`ffmpeg` and `ffprobe`; device preview requires neither. iOS audio export is not implemented.
