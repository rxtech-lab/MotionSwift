# Showcase media fixtures

These are synthetic, locally generated fixtures; no third-party footage or music is used.
`Demo.tsx` is loaded in memory with absolute bundled asset URLs substituted for its media tokens. Shared clip metadata is injected into the layer token for composition placement and navigation.

To regenerate the media from the repository root (requires FFmpeg):

```sh
ffmpeg -v error -y -f lavfi -i 'testsrc2=size=480x270:rate=30:duration=6' -f lavfi -i 'sine=frequency=440:duration=6' -c:v libx264 -preset fast -crf 25 -pix_fmt yuv420p -c:a aac -shortest Examples/MotionShowcase/Media/motion.mp4
ffmpeg -v error -y -f lavfi -i 'sine=frequency=220:duration=12' -af 'volume=0.12,afade=t=in:d=0.5,afade=t=out:st=11:d=1' -c:a aac Examples/MotionShowcase/Media/music.m4a
ffmpeg -v error -y -f lavfi -i 'gradients=size=480x270:c0=0x15314f:c1=0x25d7b5:x0=0:y0=0:x1=480:y1=270' -frames:v 1 Examples/MotionShowcase/Media/poster.png
```
