# Visual editor

> The first section describes the working editor. The numbered architecture sections below retain the broader roadmap.

## Available editor and timeline

The showcase's **Visual Editor** and the MotionStudio example both use `MotionEditorView`. On macOS a resizable split places the timeline below the canvas and transport; iPhone/iPad use a vertically divided workspace. `EditorCanvas` and `EditorTimeline` are separate public SwiftUI components taking the same `EditorModel`. That controller owns source selection, the `MotionPlayer` playhead, source write-back, notices, haptics and undo/redo.

- Select an object on either surface. On macOS, hover near any corner to reveal its outside rotation control; drag to rotate, or hold Shift for 15° snapping. The inner corner handle still resizes. Drag the timeline ruler to scrub; use its zoom menu to change frame spacing.
- Move an object by dragging its bar. Drag either edge to trim it, or open **Timing…** for exact composition-frame start and duration values. End frames are exclusive. Moving preserves local keyframe positions; trimming refuses to discard keyframes.
- **Add Keyframe** immediately captures every editable numeric style attribute at the current playhead. Move to another frame, adjust the object on the canvas or in the inspector, and click again to save that pose. Adjustments to keyed attributes preview locally until capture; moving the playhead or changing selection discards uncaptured adjustments. Capturing again at an existing frame updates its values. All captured attributes share one undo step. Drag a diamond to move it in time, or select it to edit its frame/value or delete it with native confirmation. Values hold outside the keyed range; deleting the final keyframe restores the underlying static style.
- Saves, refusals, conflicts and deletes use transient overlays. Canvas and timeline changes share one undo history and hot reload the source. Timed-out objects stay selectable in the timeline and inspector.

Timing/animation edits write a `data-ms-timeline` object literal on the original JSX opening tag, keeping its source location stable. It contains `from`, nullable `duration`, and per-property `keyframes` with object-local `frame`, numeric `value` and `easing` (`linear` or `hold`). The MotionSwift JSX runtime evaluates it for both preview and native exports without adding a layout node. This is a MotionSwift extension; unmodified browser Remotion does not evaluate this metadata.

Literal enclosing `Sequence` offsets/durations are respected. Computed Sequence timing, Loop/Freeze contexts, and descendants controlled by another object timeline are protected. Existing code-authored `interpolate`/`spring`, bound values, computed styles and spread styles are not converted to editable keyframes. Rewriting those expressions, arbitrary easing curves, media trimming, sequence reordering and composition settings remain roadmap work. Tracks are indexed from source and grouped by their owning function; reusable component definitions share timing across their rendered instances.

Run `make compiler` after changing the JSX runtime or portable edit service so both native compiler and device vendor resources include the changes.


The editor is a **pure SwiftUI** app for macOS and iOS/iPadOS. It uses no web views and no AppKit/UIKit views except the Metal-backed preview surface, which is wrapped in a SwiftUI representable. Users can:

- **select** any rendered element by clicking it in the preview,
- **drag, resize, and rotate** it on the canvas,
- **change timing**: when a `Sequence` starts, how long it lasts, and the composition duration,
- **edit animations** as keyframes on a timeline.

Every edit is written back to the TSX source. The source stays the single source of truth, so agent edits, manual edits, and code edits all work together.

The render tree is retained and source-mapped, so the editor works on real nodes, not pixels.

## Screen structure (SwiftUI)

```text
NavigationSplitView
├── Sidebar          Compositions list (from registerRoot) + layer tree of the selected frame
├── Detail
│   ├── PreviewCanvas     MetalPreviewView (Representable) + SwiftUI overlay for selection handles
│   ├── TransportBar      play/pause, frame field, fps, loop, zoom
│   └── TimelineView      tracks for Sequences + keyframe lanes for the selected element
└── Inspector (.inspector modifier)
    Properties of the selection, grouped: Layout · Transform · Appearance · Text · Animation
```

Following the app UI guidelines:

- Separate functions through navigation and sheets. Panels are never stacked on top of each other.
- **Create, update, and delete actions each get a dedicated sheet:** Add Element, Add Sequence, Edit Keyframe (easing/spring curve editor), Composition Settings (width, height, fps, duration), Rename, and Delete. On macOS, sheets use full-height content so the navigation title isn't clipped.
- Status (saving, rebuilding, rendering, write-back conflicts, deletes) appears as **overlays**, not inline banners.
- Destructive actions (delete an element or sequence, discard changes) use a native `confirmationDialog`/`alert`.
- iOS/iPadOS: haptics through `.sensoryFeedback` on selection, snapping, keyframe add/remove, and drag end.

### Preview canvas

- `MetalPreviewView` draws frames from a dedicated preview render worker (Skia Graphite → `CAMetalLayer`) at preview scale.
- Selection handles, snapping guides, and the rotation knob are **SwiftUI shapes drawn in an overlay**, positioned from the node's layout box and transform. They stay sharp at any zoom, and the engine stays free of editor UI.
- Gestures: `SpatialTapGesture` to select (⌘-click on macOS for multiple selection), `DragGesture` to move or resize, `RotateGesture` on iPad or the rotation knob on macOS, and `MagnifyGesture` to zoom the canvas.

## 1. Source stamping (compile time)

The planned source-stamp transform in `MotionCompiler` (see [typescript-and-packages.md](typescript-and-packages.md); iOS integration remains unimplemented) rewrites every **host** JSX element:

```tsx
<div style={{opacity}}>Hello</div>
// becomes
<div style={{opacity}} data-ms-src="src/Title.tsx:12:7">Hello</div>
```

- Component elements (`<Title/>`) aren't stamped. Their host output is, and the editor reconstructs the component stack from owner data the reconciler exposes in editor builds.
- `<Sequence>`, `<Series.Sequence>`, and `<Composition>` are stamped too, so the timeline can edit them.
- The compiler also emits a **source index**: for each stamp, its AST path and how each editable property is expressed (see "Property classification").
- Production render bundles strip all stamps.

## 2. Selection and inspection

1. A tap is converted from view coordinates to composition coordinates using the preview transform.
2. `MotionEditor` hit-tests the retained tree in reverse paint order. It applies each node's inverse transform and clip, and skips `pointer-events: none` nodes.
3. The hit returns `{ nodeId, src, componentStack, resolvedStyle, layoutBox, transform }`.
4. The inspector shows the values resolved at the current frame.

### Property classification

Each editable property is classified from the source index:

| Class | Source shape | Editing |
|---|---|---|
| **static** | A literal: `left: 120`, `color: '#fff'`, `rotate: '15deg'` | Edit directly. Canvas gestures rewrite the literal. |
| **animated** | `interpolate(frame, [..], [..], opts?)`, `spring({frame, …})`, `interpolateColors(frame, …)`, including inside template strings such as `` `rotate(${r}deg)` `` where `r` is one of those | Keyframe editing on the timeline. Canvas gestures add or update a keyframe at the current frame. |
| **bound** | A prop or variable that resolves to a literal in the same file | Edit the literal where it's defined, and show "edits N usages" in the inspector. |
| **computed** | Any other expression | Read-only, with "Go to source". Gestures are disabled for that property, with a note explaining why. |

## 3. Canvas editing: drag, resize, rotate

Canvas gestures map to edits on the style properties that produced the box. The mapping depends on how the element is positioned:

| Gesture | `position: absolute` element | Element in flex flow |
|---|---|---|
| Drag | `left`/`top` (or `right`/`bottom` if those are set) | `transform: translate(x, y)`, so siblings don't move. The inspector offers to switch to absolute positioning. |
| Resize (8 handles, ⇧ keeps aspect ratio, ⌥ resizes from the center) | `width`/`height` (+ `left`/`top` for top and left handles) | `width`/`height`. Shows a warning if `flex-grow` overrides it. |
| Rotate (knob, ⇧ snaps to 15°) | `transform: rotate()` around `transform-origin` | same |

Rules:

- **Transform composition:** the editor parses the existing `transform` string into a function list and edits only the matching function (`translate`, `rotate`, `scale`), keeping the order of the others. If the matching function is computed, the gesture is refused with an explanation.
- **Snapping:** to composition edges and center, sibling edges and centers, and a configurable grid. Guides are drawn in the overlay, with a haptic tick on iOS.
- **Live feedback:** while a gesture is in progress, the editor doesn't write files. It sends a **preview override** (`nodeId → style patch`) straight to the render worker, which applies it on top of the reconciled tree. That keeps updates under a frame.
- **Commit:** on gesture end, one edit operation is written (step 5), the module recompiles, the override is dropped, and the re-rendered frame must match the override frame. If it doesn't match, a mismatch overlay appears.
- **Animated properties:** dragging an element whose `left` is animated updates the keyframe at the current frame, or inserts one if the playhead is between keyframes, instead of overwriting the animation.

## 4. Timeline: time, duration, and keyframes

### Tracks

The timeline is built from the **sequence tree** that the reconciler reports for the current composition. Each `Sequence`, `Series.Sequence`, `Loop`, and `Freeze` becomes a bar with its resolved `from` and `durationInFrames`, nested to match the tree.

| Edit | UI | Source change |
|---|---|---|
| Move a sequence in time | Drag the bar | `from={30}` → `from={45}` |
| Change a sequence's duration | Drag the bar's right edge | `durationInFrames={60}` → `{90}` |
| Trim the start | Drag the left edge | `from` + `durationInFrames` together. For media, also `trimBefore`/`startFrom`. |
| Reorder `Series` items | Drag a bar onto another | Reorders the JSX children |
| Composition duration and fps | Composition Settings sheet | `durationInFrames`/`fps` on `<Composition>`, or the return value of `calculateMetadata` when it's a literal |
| Add or delete a sequence | Add Sequence sheet / delete with confirmation | Inserts or removes the JSX element |

Frame values that are computed (for example `from={fps * 2}`) are recognized when the expression is a simple linear expression of `fps` or a constant. The edit then keeps the form: `fps * 2` becomes `fps * 3` for whole-second moves, and a literal is used otherwise. Other expressions make the bar read-only.

### Keyframe lanes

Selecting an element shows one lane per animated property under its sequence bar:

- **`interpolate(frame, input, output, {easing, extrapolateLeft, extrapolateRight})`:** each `input[i]`/`output[i]` pair is a keyframe diamond. Keyframes can be dragged in time (rewrites `input[i]`), edited in value (inspector or canvas gesture), added (double-click or a canvas gesture between keyframes), and deleted (with confirmation). Ordering is enforced because Remotion requires `input` to increase strictly.
- **Frame offsets are local:** the editor accounts for the enclosing `Sequence`'s `from`, so the diamonds sit at absolute timeline positions while the source keeps local frame numbers.
- **Easing:** the Edit Keyframe sheet shows a curve editor for `Easing.bezier(...)` and presets (`Easing.in/out/inOut` with `quad`, `cubic`, `sin`, `exp`, `circle`, `back`, `elastic`, `bounce`). The source `easing` option is rewritten.
- **`spring({frame, fps, config, delay, durationInFrames})`:** shown as a single segment with a curve preview. The sheet edits `delay` (dragging the start), `durationInFrames`, and `config` (`mass`, `stiffness`, `damping`, `overshootClamping`). Values derived from a spring (`interpolate(spring(...), [0, 1], [a, b])`) expose `a` and `b` as the start and end values.
- **Static → animated:** "Animate" on a static property inserts `interpolate(frame, [f, f + 30], [v, v])`. It adds `const frame = useCurrentFrame()` and the imports if missing, and handles units (`` `${x}px` ``, `` `rotate(${r}deg)` ``) by interpolating the number and keeping the template.
- **Animated → static:** "Remove animation" (with confirmation) replaces the expression with the value at the current frame.

Curve values come from the **engine**, not from a Swift reimplementation. The lane asks the JS runtime to evaluate the property's expression over the visible frame range. That keeps the timeline's curves identical to the render ([compatibility.md → Motion determinism](compatibility.md#motion-determinism)).

## 5. Write-back (edit operations)

All UI edits become operations sent to the AST edit service. That's a ts-morph worker running in a Node/Bun sidecar on macOS, or inside JSC on iOS.

```jsonc
{ "op": "setStyle",        "src": "src/Title.tsx:12:7", "key": "left", "value": "160" }
{ "op": "setTransformFn",  "src": "src/Title.tsx:12:7", "fn": "rotate", "args": ["30deg"] }
{ "op": "setText",         "src": "src/Title.tsx:12:7", "value": "New title" }
{ "op": "setKeyframes",    "src": "src/Title.tsx:12:7", "key": "opacity",
  "input": [0, 30, 45], "output": [0, 1, 1], "easing": "Easing.out(Easing.cubic)" }
{ "op": "setSpring",       "src": "src/Logo.tsx:8:15", "delay": 10, "config": { "damping": 12 } }
{ "op": "setSequenceTime", "src": "src/Main.tsx:20:5", "from": 45, "durationInFrames": 90 }
{ "op": "setComposition",  "src": "src/Root.tsx:6:3", "durationInFrames": 300, "fps": 30 }
{ "op": "insertElement",   "parentSrc": "src/Main.tsx:18:3", "index": 2, "jsx": "<div style={{…}} />" }
{ "op": "removeElement",   "src": "src/Main.tsx:24:7" }
```

- The service finds the node by `src` and re-validates it against the file's content hash, so it never edits a stale location. If the location is stale, the editor shows a "source changed, reselect" overlay.
- It changes only the targeted expression, keeps formatting (Prettier on the changed range), and preserves comments.
- **Undo/redo:** every operation returns its inverse. The SwiftUI `UndoManager` holds the pairs, so ⌘Z works across canvas, timeline, and inspector edits.
- **Batching:** a gesture produces exactly one operation, applied on gesture end. Multiple selection produces one operation per element in a single undo group.
- Agent edits and manual edits go through the same service, so both stay consistent with each other.

## 6. Hot reload and scrubbing

- After a write, `MotionCompiler` re-transforms only the changed modules, using the content-hash cache. The runtime loads the updated module graph into a fresh `JSContext`, keeps the current frame and selection (re-resolved by `src`), and re-renders.
- Target: under 150 ms from gesture end to the committed frame. During the gesture, preview overrides keep it under one frame.
- Scrubbing the timeline renders one frame per display refresh and drops intermediate frames rather than queueing them. Target: under 8 ms per frame for text and shape compositions at 1080p, which keeps 120 Hz scrubbing smooth.
- The editor's undo stack holds operation pairs, not file snapshots, so the editor state survives a hot reload.

## Editor tests

These are additions to [tests/README.md](../tests/README.md):

- `tests/editor-fixtures/<case>/`: `before.tsx` + `op.json` → `after.tsx`, compared byte for byte. There is a case for every operation and every property class, plus the inverse operation (applying the inverse must restore `before.tsx` exactly).
- **Gesture → operation mapping:** unit tests in `MotionEditor` for absolute vs flex positioning, transform-list editing, snapping, and keyframe insertion between existing keyframes.
- **Round trip:** apply the operation, re-render, and pixel-compare with a golden of the expected result. Also compare the committed frame with the preview-override frame, which must match exactly.
- **Timeline mapping:** sequence trees with nested `from` offsets resolve to the expected absolute positions for keyframes and bars.
- **SwiftUI UI tests:** select, drag, resize, rotate, timeline bar drag, and the keyframe sheet, run with XCUITest on a fixture project.
