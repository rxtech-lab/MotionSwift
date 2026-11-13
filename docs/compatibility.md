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
| `@remotion/paths`, `@remotion/shapes` | ✅ subset | 3 | Pinned DOM-free helpers listed in the executable effects contract below. |
| `@remotion/noise` | ⛔ | – | Not in the vendor graph. |
| `@remotion/transitions` | 🟡 partial | 3 | `TransitionSeries`, `linearTiming`, fade/slide/wipe execute; raster acceptance is tracked below. |
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
| `svg` + `path`, `rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `g`, `defs`, `linearGradient`, `radialGradient`, `stop`, `clipPath`, `mask` | 🟡 partial | React commits a validated vector island to SkSVG. Only its root has a Yoga/editor box. The supported fixture subset passes the strict Remotion raster gate on CPU and Metal; this does not cover arbitrary SVG documents. |
| Inline SVG `text`, `tspan`, `pattern`, `use`, `image`, `foreignObject`, `filter`, SMIL | ⛔ | Never substitute SVG text for HTML paragraph layout. Legacy XML construction into data-URI images remains separate. |
| External `.svg` via `<Img src>` | 🟡 partial | `objectFit: contain`, staged/public files or HTTP(S) URLs ending in `.svg`; SkSVG image contract. The external SVG fixture passes strict raster checks on CPU and Metal. Existing SVG data-URI delivery retains its original raster path. |
| `canvas` | ⛔ | |
| R3F elements inside `<ThreeCanvas>` (`mesh`, `group`, `primitive`, `*Geometry`, `mesh*Material`, lights, `color`/`fog` attachments) | 🟡 | Drawn by the native 3D renderer; see [3D support](three-d.md). |
| `video`, `audio` (raw HTML) | ⛔ | Use `OffthreadVideo` / `Audio` instead. |
| Form elements, `table`, `iframe` | ⛔ / 🌐 | |

## CSS subset

Only inline `style` props are supported in v1. `className` with Tailwind is planned for a later phase as a compile-time transform from Tailwind classes to inline styles. Stylesheets, selectors, and the cascade are not supported. Inheritance is supported only for text properties (`color`, `font-*`, `line-height`, `letter-spacing`, `text-align`, `text-transform`, `white-space`).

| Area | Properties | Phase |
|---|---|---|
| Box & layout | `display: flex/inline-flex/none` (plus leaf inline/inline-block flex items), `flex`, `flex-direction/wrap/grow/shrink/basis`, `justify-content`, `align-items/self`, `position: relative/absolute`, `top/right/bottom/left`, `inset`, `width/height/min/max`, `margin`, `padding`, `gap`, `box-sizing`, `aspect-ratio`, `overflow: hidden/visible`, `z-index` | 0–2 (Yoga) |
| Units | `px`, `%`, unitless, `em`, `rem`, `vw/vh` (relative to the composition), `deg/rad/turn` | 0–2 |
| Color | named, hex, `rgb()/rgba()`, `hsl()/hsla()`, `transparent`, `currentColor` | 0 |
| Background | `background-color`, `background-image: linear-gradient/radial-gradient/conic-gradient/url()`, `background-size/position/repeat` | 3 |
| Border | `border*`, `border-radius` (elliptical too), `outline` | 2–3 |
| Effects | `opacity`, `box-shadow` (incl. inset, multiple), `filter: blur/brightness/contrast/grayscale/saturate/hue-rotate/drop-shadow/invert/sepia`, `mix-blend-mode`, `backdrop-filter: blur` | 3 |
| Clipping | `clip-path: inset/circle/ellipse/polygon/path()`, `mask-image: linear-gradient` | 3 |
| Transform | `transform` (2D functions plus `perspective`/`rotateX/Y`/`translateZ` as 4×4), `transform-origin`, `perspective` | 0 (2D), 3 (3D) |
| Text | `font-family/size/weight/style`, `line-height`, `letter-spacing`, `text-align`, `text-transform`, `white-space`, `word-break`, `text-shadow`, `-webkit-text-stroke`, `text-overflow: ellipsis`, `-webkit-line-clamp`, `font-variant-numeric: tabular-nums`, `background-clip: text` | 0 (basic), 3 (rest) |
| Image | `object-fit`, `object-position` | 2 |
| Rejected | `display: grid`/`block` flow layout, inline boxes outside flex items, `float`, `position: fixed/sticky`, CSS animations/transitions, `@keyframes`, `:hover`/pseudo-elements, `writing-mode`, `columns` | ⛔ |

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

## Executable core contracts (2026-11-13)

This table narrows the roadmap rows above to the currently accepted box/shim values.
It addresses census blockers #3 and #5 in [Phase 0 validation](phase0-validation.md#remaining-blockers).
It does not rerun or supersede that historical real-composition census.

| Contract | Accepted values and boundaries | Verification |
|---|---|---|
| `spring` | Existing `mass`, `stiffness`, `damping` (positive), `overshootClamping`, `from`/`to`; positive finite `durationInFrames`, `durationRestThreshold` in `(0,1)`, finite `delay`, boolean `reverse`. Duration stretching, reversal, then delay. Fractional and negative sample frames accepted; negative physical time stays at `from`. | Upstream numerical tests and 30-frame V8 → JSC trace, tolerance `1e-9`. |
| `measureSpring` | Positive finite `fps`; same config; `threshold` in `(0,1)`, default `.005`. Last threshold crossing followed by one second without another crossing. Deprecated `from`/`to` accepted without affecting duration. Nonsettling springs fail after 1,000,000 sampled frames. | Upstream thresholds `.001`, `.005`, `.01`, fps 10/30/60, damping 5/10/20/35. |
| `Series`, `Series.Sequence` | Direct sequence children (arrays and absent children allowed); required positive integer duration, `Infinity` only for final child; signed integer `offset` shifts this and subsequent starts, including overlaps. Series accepts Sequence timing/layout props, default `layout="none"`. Fragments/wrapper components are rejected. | Nested Sequence/Series goldens at starts, ends, overlaps and gaps. |
| `Sequence` | Integer `from`, positive integer duration or `Infinity`; inclusive start/exclusive end. Nested frames subtract every enclosing offset; nearest sequence limits `useVideoConfig().durationInFrames`. `layout="absolute-fill"` (default) or `"none"`; style requires absolute-fill. | Existing sequence fixtures plus `SeriesTiming`. |
| `Easing` | `linear`, `quad`, `cubic`, `sin`, `exp`, `circle`, `step0`, `step1`, `ease`, `bounce`; factories `poly(n)`, `back(s=1.70158)`, `elastic(b=1)`, `bezier(x1,y1,x2,y2)` (x controls in `[0,1]`); `in`, `out`, `inOut`. Easing progress is normally `[0,1]`. | Installed Remotion helper comparisons; bezier/ease/back also traced in JSC. |
| `random` | Finite numeric or string seed; no global PRNG state. Repeated/out-of-order evaluation gives the same upstream value, including UTF-16 string seeds. `null`, missing seeds and non-finite numbers rejected. | Exact Remotion values and per-frame JSC trace. |
| Colors | All CSS named colors, case insensitive; transparent; `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`; `rgb`/`rgba` with numeric/percentage channels; `hsl`/`hsla` with number/degree hue and percentage saturation/lightness. Comma or space/slash functional forms; channels clamp to their CSS ranges. `currentColor` resolves inherited box color, initially black. No wide-gamut/CSS variable colors. | `BorderOrder`, upstream `interpolateColors` serialized channel comparisons. |
| `interpolateColors` | Same color literals (no context-dependent `currentColor`); linear sRGB channel interpolation, endpoint clamping, byte-quantized alpha inputs and 3-decimal output alpha. | Upstream named/hex/rgb/hsl comparisons, including out-of-range progress. |
| Borders | `border`, `borderTop/Right/Bottom/Left`: optional numeric/px nonnegative width (default 3), `solid`/`none`/`hidden` (default none), one color (default currentColor). Uniform `borderWidth/Color/Style` and per-side longhands; longhands override shorthand. Width/color/style multi-value lists, dashed/dotted/double and other line styles rejected. Borders reserve Yoga space and paint inside the border box. Rounded borders require uniform width/color; elliptical/per-corner radii remain unsupported. | `BorderOrder`, native size and rejection tests. |
| Box sizing | `border-box` by default, matching Remotion's global reset; explicit `content-box` adds border/padding outside width/height. | Native layout dimensions and Remotion border golden. |
| `zIndex` | Integer or `auto`; ascending paint order, stable source order for ties, negative indices before auto/zero. Descendants of auto-z boxes participate in the enclosing context. Explicit z-index, transform, opacity and effect groups are atomic contexts. Source/editor paths remain tied to original child indices. | Sibling and nested-auto/explicit-context native tests and `NestedOrder` reference. |
| `transformOrigin` | One/two CSS origin components: left/center/right, top/center/bottom, percentages, px lengths, unitless zero; vertical-first keyword pairs accepted. Third/z component rejected. | Keyword and percentage/px golden; invalid origin diagnostic. |
| `flex` | Nonnegative number; `none` = `0 0 auto`, `auto` = `1 1 auto`, `initial` = `0 1 auto`; one grow, grow+shrink, grow+basis or grow+shrink+basis. Basis accepts px, percentage or `auto`. Explicit grow/shrink/basis override shorthand. | `FlexOrigin` and native `[60,120,40]` widths / `[0,70,200]` x positions. |
| Inline boxes | `display: inline-flex` uses Yoga flex layout when placed in a flex container. `inline`/`inline-block` leaf or paragraph flex items are blockified, matching browser flex-item layout. They require an explicitly flex/inline-flex parent. Mixed inline boxes, inline boxes outside flex parents, and general block flow remain explicit diagnostics. Paragraph runs have their own text contract. | Inline-flex reference; compiler still rejects unsupported display values. |
| Visually inert properties | `pointerEvents: auto/none`, `userSelect: auto/none/text/all`, and string `cursor` accepted deliberately; they do not affect offline frames. | Included in type and border goldens; invalid pointerEvents rejection. |
| Environment | `getRemotionEnvironment`/`useRemotionEnvironment`: rendering true; studio/player/client-side-rendering false. | Pure worker environment; no interactive studio emulation. |

References: [spring timing](https://www.remotion.dev/docs/spring),
[Series offsets](https://www.remotion.dev/docs/series), [Easing](https://www.remotion.dev/docs/easing),
[seeded random](https://www.remotion.dev/docs/random). Math is implemented independently; pinned upstream
Remotion is used only to produce reference values and frames. Regenerate motion reference values with
`node tests/tools/generate-core-traces.mjs`; regenerate image references with `make goldens`.
The upstream type fixture checks application calls with upstream declaration internals skipped because
that package references optional Zod/Bun types; subset declarations are checked without skipping libraries.


## Executable effects and SVG contract

This section describes implemented runtime syntax; the broad CSS table above remains a roadmap.
The effects/SVG task remains incomplete until the cross-engine raster gate passes. Successful parsing,
native rendering and deterministic repeats do not establish that acceptance.
The strict parsers reject unsupported properties, unconsumed tokens, nonfinite values and unsupported units.
String-valued declarations describe a grammar, not support for arbitrary browser CSS.

| Property | Accepted contract | Rejected / remaining gaps |
|---|---|---|
| `background` / `backgroundImage` | One `linear-gradient()` with an optional `deg` angle or cardinal `to top/right/bottom/left`; one explicit `radial-gradient(ellipse <rx>px <ry>px at <x> <y>, ...)`. Two to 256 stops; colors without whitespace; omitted or ascending percentage stops in 0–100%. Centers accept px/%. | Conic/repeating gradients, layered backgrounds, URL images, extent keywords, stop hints, stop lengths outside percentages, color-space selectors. |
| `boxShadow` | Comma-separated `xpx ypx [blurpx [spreadpx]] color`, optional leading/trailing `inset`; blur >= 0. Whole group opacity/filter applies to the result. | Color must be last and contain no whitespace. Browser corner blur raster parity remains separately measured. |
| `filter` | Ordered `blur(px)`, `brightness`, `contrast`, `grayscale`, `saturate`, `invert`, `sepia`, `opacity` with finite nonnegative unitless/% amounts; `hue-rotate(deg)`; `drop-shadow(xpx ypx [blurpx] color)`. | `url()`/SVG filter references, nested color functions with whitespace, unsupported units. Drop shadows have no spread/inset. |
| `backdropFilter` | One `blur(px)`, clipped to the element's rounded border box and sampling previously painted siblings. | Same-element opacity < 1, filter, mask or non-normal blending are rejected pending full CSS backdrop-root composition. |
| `mixBlendMode` | normal, multiply, screen, overlay, darken, lighten, color-dodge, color-burn, hard-light, soft-light, difference, exclusion, hue, saturation, color, luminosity. | Explicit CSS `isolation` and browser stacking contexts outside the supported box model. |
| `clipPath` | `inset()` with 1–4 px/% lengths; explicit `circle(radius at x y)` / `ellipse(rx ry at x y)`; `polygon()` of at least three px/% pairs; `path('SVG path')`. | `round`, geometry-box suffixes, evenodd arguments, URL clip references. |
| `maskImage` | One supported gradient as an alpha mask over the filtered subtree, before group opacity/blend. | Multiple masks, luminance mode, mask URL/position/size/repeat/composite. |
| `transform` | Existing 2D functions plus scaleX/Y/Z, skewX/Y, rotateX/Y/Z, translateZ/3d, scale3d, matrix/matrix3d and perspective(px); CSS source-order 4×4 multiplication projected onto a flat element plane. | `transformStyle: preserve-3d`, ancestor `perspective`, backface visibility, shared depth sorting. `perspective()` is a transform-list function, not the ancestor property. |
| Advanced HTML text | Remains dependent on paragraph layout task `65656DA1-6C96-471C-B752-F32F953B0A39`. | `textShadow`, text stroke, ellipsis/clamp, tabular numerals and background-clip:text remain rejected. No SVG approximation is used. |

Inline SVG accepts the presentation attributes declared in `jsx-runtime.d.ts`: geometry, fill/stroke,
opacity, SVG transforms, dash animation, gradients, local clip/mask references and viewBox sizing.
React/frame-driven changes are committed on every sample, including reverse seeks. Descendants are
serialized into one atomic vector document and do not appear as individually editable layout boxes.
Unknown elements/attributes, nonfinite numeric attributes, event handlers, external resource references,
CSS styles outside the declared presentation subset, scripts and foreign HTML fail with `ms/unsupported-*`.
SVG `text`/`pattern` declarations are retained solely for existing user XML serializers that create data-URI
images; they are rejected as inline hosts. External images retain the earlier SkSVG image behavior,
including its separate SVG text normalization. This is not HTML text support.

The precompiled package graph exposes only:

- `@remotion/paths`: `getLength`, `evolvePath`, `translatePath`, `scalePath`.
- `@remotion/shapes`: `makeRect`, `makeCircle`, `makeEllipse` (path/metadata generators, no components).
- `@remotion/transitions`: `TransitionSeries.Sequence`, `.Transition`, `linearTiming`;
  `fade`, `slide`, `wipe` from their respective subpaths. Sequences require positive integral durations;
  transitions must separate two sequences, be shorter than either, and cannot overlap a neighboring transition.
  Four cardinal directions are supported. Custom presentations, spring timing, premount/postmount, offsets,
  layout/style overrides and other transition packages are rejected.

Paths/shapes use pinned MIT-licensed 4.0.542 algorithms with their license notices in the packaged vendor
resources. The transition subset is an independently implemented scheduler over our existing Sequence/frame context;
the reference-only transitions dependency is not bundled into the runtime.
Reviewed reference fixtures live in `tests/compositions/visuals/Effects.tsx`, registered in `tests/fixtures.json`.
`make visual` retains the existing 0.3% changed-pixel threshold on CPU and Metal; implementation acceptance
must distinguish parser/native unit results from cross-engine raster parity.

Focused core verification (all six original fixtures plus four new contract fixtures):

```sh
make compiler
npm test --prefix tests
swift test --no-parallel --filter 'box|javaScriptCoreMotionMatchesRemotionTrace|independentFramesRespectSequenceAndProps|retainedRuntimeIsIndependentAndInvalidates|retainedAsyncFramesMatchSequentialAndShuffledPixels|rendersSkiaPNGAndRejectsUnknownStyles|rendererClearsPreviousFrameAndChecksDimensions'
MOTIONSWIFT_VISUAL_OUTPUT=tests/reports/visual-core MOTIONSWIFT_FIXTURE_IDS=core/solid,core/boxes,motion/translate,core/flex,core/opacity,motion/sequence-spring,core/border-order,core/flex-origin,motion/series-timing,core/nested-order make visual
```

Without `MOTIONSWIFT_FIXTURE_IDS`, `make visual` runs the complete manifest, including independently
maintained effects fixtures. A selected run records its exact fixture IDs in each backend's result
JSON; it does not establish parity for the other fixtures or the private real-composition corpus.

### Effects verification status (2026-11-14, macOS arm64)

The complete visual manifest passes on CPU and Metal: 62 samples per backend, comprising
42 core samples and 20 effects samples. Every repeat is exact. The existing exact RGBA
comparison and 0.3% changed-pixel allowance are unchanged; no reference PNG was replaced.
Maximum changed-pixel percentages across the effects samples:

| Fixture | CPU | Metal |
|---|---:|---:|
| Gradients | 0.1389% | 0.1667% |
| Shadows | 0.2118% | 0.2882% |
| Filters | 0.1528% | 0.1528% |
| Blending | 0% | 0% |
| Clip / filter / mask / transparency interaction | 0.2378% | 0.2396% |
| Backdrop blur | 0.2083% | 0.2083% |
| Flat-plane 3D transforms | 0.1528% | 0.2413% |
| Inline SVG (maximum across three frames) | 0.1597% | 0.2552% |
| External SVG | 0.2622% | 0.2622% |
| Fade transition | 0% | 0% |
| Slide transition | 0% | 0% |
| Wipe transition | 0% | 0% |

The native implementation aligns gradient dithering, Gaussian weights, intermediate color
rounding, clipping coverage and SVG antialiasing with the pinned Chrome fixtures. Small
Gaussian blurs use separable runtime filters; larger radii use Skia's native blur on the
selected backend. Metal filters use shader tiling for transparent borders on devices without
hardware border samplers; solid rounded boxes preserve analytic coverage. Thread-local Rust
runtime-effect caches are bounded. SVG shader and
external-document caching remain performance work. Existing data-URI SVG scenes keep their
original raster path; a retained renderer can switch between this path and CSS effects.

Transition fixtures now declare their incoming background during overlap. All nine freshly
rendered pinned-Chrome transition references exactly match the existing PNGs; only source
provenance metadata changed. At 720p, the external SVG video also passes the unchanged 0.98
SSIM gate on CPU and Metal (0.9970). Benchmark references include the project's public
assets, and single-frame benchmark fixtures render two frames to form a valid video.

Artifacts: `tests/reports/visual/{cpu,gpu}/{results.json,index.html}`. These results cover the
manifest's supported subset, not arbitrary CSS/SVG or private compositions. Advanced HTML
text effects remain blocked on the paragraph task above.

For isolated builds, `SWIFT_BUILD_FLAGS` can supply a separate `--scratch-path` to
`make build` / `make visual`; set `MOTIONSWIFT_BIN` to that build's CLI path.
`MOTIONSWIFT_VISUAL_OUTPUT` isolates reports, and `MOTIONSWIFT_FIXTURE_IDS` selects a subset.
A selected run establishes parity only for its recorded fixture IDs.
