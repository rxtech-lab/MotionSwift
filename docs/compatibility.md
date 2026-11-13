# Remotion compatibility

> Current executable behavior and remaining work: [runnable implementation](current-implementation.md). This document describes the target architecture and roadmap.

MotionSwift is compatible with a **defined subset** of Remotion. Code inside the subset renders unchanged. Code outside it is rejected by lint at generation time, so the agent (or user) can rewrite it before a render starts.

Each row below has a status that the implementation must keep up to date:

- ✅ supported
- 🟡 planned for a specific phase (see [implementation-plan.md](implementation-plan.md))
- ⛔ rejected by lint
- 🌐 WebKit fallback (macOS only, opt-in)

## `remotion` package API

`@motionswift/remotion` (`js/remotion-shim`) is aliased as `remotion` by the resolver. Its `.d.ts` files mirror Remotion's types for the supported subset only, so unsupported APIs fail in `tsc` too. See [typescript-and-packages.md](typescript-and-packages.md).

| API | Target | Phase | Notes |
|---|---|---|---|
| `useCurrentFrame`, `useVideoConfig` | ✅ | 0 | Driven by the frame scheduler. |
| `Composition`, `Still`, `registerRoot`, `Folder` | ✅ | 0 | Used to enumerate compositions and their `durationInFrames`, `fps`, `width`, `height`, `defaultProps`, and `calculateMetadata`. |
| `AbsoluteFill` | ✅ | 0 | |
| `interpolate`, `interpolateColors`, `Easing`, `spring`, `measureSpring`, `random` | ✅ | 0 | Pure JS, executed in JSC. See [Motion determinism](#motion-determinism). |
| `Sequence`, `Series`, `Loop`, `Freeze` | ✅ | 2 | Frame remapping in the shim. |
| `Img`, `staticFile` | ✅ | 2 | Decoded by `MotionMedia`. Uses `delayRender` internally. |
| `delayRender`, `continueRender`, `cancelRender` | ✅ | 2 | A frame is not rasterized until all handles resolve. The timeout matches Remotion's default. |
| `OffthreadVideo`, `Video` | 🟡 | 4 | Both map to native frame extraction. `playbackRate`, `startFrom`/`endAt`, `trimBefore`/`trimAfter`, `muted`, and `volume` are supported. |
| `Audio` | 🟡 | 4 | Native preview and macOS export mixing with per-frame volume. See [media contract](media-compositions.md). `useAudioData` helpers are not implemented. |
| `@remotion/google-fonts`, `@remotion/fonts` `loadFont` | 🟡 | 4 | Fonts are registered in the Skia font collection. |
| `@remotion/paths`, `@remotion/shapes`, `@remotion/noise` | ✅ | 3 | Pure JS output → SVG paths. |
| `@remotion/transitions` | 🟡 | 3 | Built on the supported subset (opacity, transforms, clip). |
| `@remotion/three` (`ThreeCanvas`) + React Three Fiber elements, `three` math subset, USD/USDZ models | 🟡 | 4 | Native Metal port of three.js r187 shading; keyframed cameras via `useThree`, meshes, 13 geometries, 6 material types, ambient/hemisphere/directional/point/spot lights, fog, transparency, USDZ via `useLoader(USDLoader)`. No textures, shadows or `useFrame`. See [3D support](three-d.md). |
| `@remotion/lottie`, `@remotion/gif` | ⛔ → 🟡 later | – | `lottie` can come later via Skottie, which is part of Skia. |
| `<IFrame>`, arbitrary HTML via `dangerouslySetInnerHTML` | ⛔ / 🌐 | – | |
| `getRemotionEnvironment`, `useRemotionEnvironment` | ✅ | 2 | Reports `isRendering` / `isStudio` equivalents. |

**Licensing:** before reusing any code from the `remotion` package in the shim (rather than writing it clean-room against the documented behavior), review the Remotion License terms with legal. The math functions are small and well specified, and the parity tests in [`tests/`](../tests/README.md) check behavior, not shared source.

## Host elements

### Maps

OpenStreetMap-style raster tile layouts and prepared MapKit snapshot images can use
`Img` with frame-driven overlays. Interactive Leaflet / React Leaflet and MapKit JS
are **not integrated** with the native JavaScriptCore renderer; neither is native
MapKit snapshot generation. [Map regression coverage](../tests/maps/README.md) compares
offline synthetic tile/snapshot compositions against Remotion on CPU and GPU in push CI.
This verifies image compatibility, not live map services or authorization.

| Element | Status | Notes |
|---|---|---|
| `div`, `span`, `p`, `h1`–`h6`, `section`, `header`, `footer`, `main` | ✅ | All are boxes. Text elements get user-agent defaults (margins, font sizes) that match Chrome. |
| `img` | ✅ | Same path as `<Img>`. |
| `svg` + `path`, `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `g`, `defs`, `linearGradient`, `radialGradient`, `stop`, `clipPath`, `mask`, `text` | 🟡 3 | Built directly as Skia draw ops. Inline SVG goes through our own SVG node mapping (so it stays editable), not SkSVG. |
| External `.svg` via `<Img src>` | 🟡 3 | Rendered with SkSVG. |
| `canvas` | ⛔ | |
| R3F elements inside `<ThreeCanvas>` (`mesh`, `group`, `primitive`, `*Geometry`, `mesh*Material`, lights, `color`/`fog` attachments) | 🟡 | Drawn by the native 3D renderer; see [3D support](three-d.md). |
| `video`, `audio` (raw HTML) | ⛔ | Use `OffthreadVideo` / `Audio` instead. |
| Form elements, `table`, `iframe` | ⛔ / 🌐 | |

## CSS subset

Only inline `style` props are supported in v1. `className` with Tailwind is planned for a later phase as a compile-time transform from Tailwind classes to inline styles. Stylesheets, selectors, and the cascade are not supported. Inheritance is supported only for text properties (`color`, `font-*`, `line-height`, `letter-spacing`, `text-align`, `text-transform`, `white-space`).

| Area | Properties | Phase |
|---|---|---|
| Box & layout | `display: flex/none`, all flexbox properties, `position: relative/absolute`, `top/right/bottom/left`, `inset`, `width/height/min/max`, `margin`, `padding`, `gap`, `box-sizing`, `aspect-ratio`, `overflow: hidden/visible`, `z-index` | 0–2 (Yoga) |
| Units | `px`, `%`, unitless, `em`, `rem`, `vw/vh` (relative to the composition), `deg/rad/turn` | 0–2 |
| Color | named, hex, `rgb()/rgba()`, `hsl()/hsla()`, `transparent`, `currentColor` | 0 |
| Background | `background-color`, `background-image: linear-gradient/radial-gradient/conic-gradient/url()`, `background-size/position/repeat` | 3 |
| Border | `border*`, `border-radius` (elliptical too), `outline` | 2–3 |
| Effects | `opacity`, `box-shadow` (incl. inset, multiple), `filter: blur/brightness/contrast/grayscale/saturate/hue-rotate/drop-shadow/invert/sepia`, `mix-blend-mode`, `backdrop-filter: blur` | 3 |
| Clipping | `clip-path: inset/circle/ellipse/polygon/path()`, `mask-image: linear-gradient` | 3 |
| Transform | `transform` (2D functions plus `perspective`/`rotateX/Y`/`translateZ` as 4×4), `transform-origin`, `perspective` | 0 (2D), 3 (3D) |
| Text | `font-family/size/weight/style`, `line-height`, `letter-spacing`, `text-align`, `text-transform`, `white-space`, `word-break`, `text-shadow`, `-webkit-text-stroke`, `text-overflow: ellipsis`, `-webkit-line-clamp`, `font-variant-numeric: tabular-nums`, `background-clip: text` | 0 (basic), 3 (rest) |
| Image | `object-fit`, `object-position` | 2 |
| Rejected | `display: grid`/`inline`/`block` flow layout, `float`, `position: fixed/sticky`, CSS animations/transitions, `@keyframes`, `:hover`/pseudo-elements, `writing-mode`, `columns` | ⛔ |

> `display: block` is common in agent output. In v1 the linter rewrites `display: block` to `display: flex; flex-direction: column` only when it can prove the result is identical: the children are all block-level and there is no inline text mixed with elements. Otherwise it reports an error.

## Motion determinism

- Motion math (`interpolate`, `spring`, `Easing.*`) runs as JS in JSC. It is never ported to Swift.
- JS numbers are IEEE-754 doubles in every engine, so arithmetic is identical. **Exception:** transcendental `Math` functions (`Math.exp`, `Math.sin`, `Math.cos`, `Math.pow`) are not required to be correctly rounded. JSC and V8 can differ by 1 ulp. For springs, this produces differences around 1e-15 in position, which are far below one pixel.
- CI checks this ([tests/README.md → motion parity](../tests/README.md#layer-1--motion-parity)). Values are traced in Node/V8 and in MotionSwift/JSC, and the test asserts `|Δ| ≤ 1e-9` for all sampled frames.
- Rendering must be a pure function of `(bundle, props, frame)`. `Math.random()` and `Date.now()` are replaced in the runtime with deterministic versions, and lint warns about them in favor of `random(seed)`.

## Lint rules (`js/lint`)

Lint runs on the bundle input before render and in the agent's generation loop. It reports errors with `file:line:col` and a suggested fix.

| Rule | Example |
|---|---|
| `ms/unsupported-element` | `<canvas>`, `<iframe>`, `<table>` |
| `ms/unsupported-css-property` | `display: 'grid'`, `position: 'fixed'` |
| `ms/unsupported-css-value` | `filter: 'url(#f)'` |
| `ms/no-classname` | `className` (until Tailwind support lands) |
| `ms/no-nondeterminism` | `Math.random()`, `Date.now()`, `new Date()` without arguments |
| `ms/no-raw-media` | `<video>`, `<audio>` |
| `ms/unsupported-package` | importing `@remotion/three`, `@remotion/lottie`, ... |
| `ms/dynamic-style-key` | computed style keys that lint can't verify (a warning, checked at runtime in `--strict`) |

Every rule has at least one fixture in `tests/lint-fixtures/` that must fail with that rule ID.
