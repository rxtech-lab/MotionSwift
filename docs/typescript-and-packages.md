# TypeScript compatibility, compilation, and packages

> Current executable behavior and remaining work: [runnable implementation](current-implementation.md). The macOS package currently bundles native TypeScript 7 (tsgo) for compilation and type checking, with esbuild linking emitted JavaScript, with no runtime Node dependency. The cross-platform module cache, editor transforms, and distribution sections below remain roadmap items.

This doc covers how a Remotion TSX project becomes JavaScript that JavaScriptCore can run, how TypeScript users get type-level compatibility checks, and which npm packages MotionSwift publishes.

## Goals

1. An existing Remotion project (`package.json`, `tsconfig.json`, `src/index.ts` → `registerRoot`) compiles with **no source changes**, as long as it stays inside the [supported subset](compatibility.md).
2. The **same compiler** runs on macOS, iOS, and Linux. iOS can't spawn processes or run Node, so the compiler must be a library linked into the app, not a CLI.
3. Unsupported APIs and CSS show up as **TypeScript errors in the IDE**, before lint or render.
4. Compiled output keeps exact source locations (for errors and for editor stamping).

## Pipeline

```text
project TS/TSX/JS + JSON
  → native TypeScript 7 (tsgo): emit ES2022 JavaScript and transform JSX
  → original-source subset inspection in JavaScriptCore
  → esbuild: link emitted JavaScript with bundled React and the Remotion shim
  → JavaScriptCore (MotionRuntime)
```

The bundled native compiler is TypeScript 7.0.2, the released tsgo compiler, whose executable is now named `tsc`. It handles both compilation and type checking. No Node process or npm installation is needed at runtime.

**Type checking is separate from rendering.** Compilation uses `noCheck` to emit without semantic type checking. `checkTypes` uses the same subset declarations and compiler settings with `noEmit`, and returns structured diagnostics. Both operations use a generated configuration rather than the project's tsconfig. JavaScript and JSON imports are included in the emitted project tree, and JSX is transformed by tsgo before bundling. Syntax inspection operates on original sources so unsupported JSX and dynamic imports/requires are still rejected.

### Platform integration

The current macOS implementation launches bundled native TypeScript and esbuild executables for Apple Silicon and Intel. esbuild only links JavaScript; it does not compile project TypeScript. iOS cannot launch these subprocesses, so iOS needs precompiled bundles or a future in-process integration. Module caching, hot reload, source maps, and editor source stamping remain planned.

## TypeScript feature support

| Feature | Supported | Notes |
|---|---|---|
| All type-only syntax (types, interfaces, generics, `satisfies`, `as const`, type-only imports and exports) | ✅ | Stripped. |
| `enum`, `namespace` (non-ambient) | ✅ | Transformed by native TypeScript. |
| `const enum` across files | ⛔ | Requires `isolatedModules: true`, the same rule esbuild and Vite apply. Enforced by the tsconfig preset. |
| Decorators (TC39 stage 3) | ✅ | Rare in Remotion code. |
| Legacy `experimentalDecorators` / `emitDecoratorMetadata` | ⛔ | |
| `paths` aliases in `tsconfig.json` | ✅ | Read by the resolver. |
| `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.json` | ✅ | CommonJS dependencies are wrapped. |
| `import x from './image.png'` (and other assets) | ✅ | Resolves to an asset URL served by `MotionMedia`, like `staticFile()`. |
| `import './styles.css'` and CSS modules | ⛔ | Inline styles only ([compatibility.md](compatibility.md#css-subset)). |
| Dynamic `import()` | ✅ | Resolved from the precomputed graph. Only static string specifiers are allowed. |
| Top-level `await` | ⛔ in v1 | |

**JS target:** output is downleveled to the lowest JSC version we support. That is ES2022 for macOS 14+ and iOS 17+, and for the pinned `libjavascriptcoregtk` on Linux. Pinning one target keeps output identical across hosts.

## Module resolution and dependencies

### Aliases (applied by the resolver)

| Import | Resolves to |
|---|---|
| `remotion` | `@motionswift/remotion` (the shim) |
| `react`, `react/jsx-runtime` | Pinned React version shipped in the vendor bundle |
| `react-dom`, `react-dom/client` | A stub that throws a clear "not supported in MotionSwift" error |
| `@remotion/paths`, `@remotion/shapes`, `@remotion/noise`, `@remotion/transitions` | The real packages (pure JS), with a version range checked against the shim |
| `@remotion/google-fonts/*`, `@remotion/fonts` | `@motionswift/fonts` (registers fonts with Skia instead of the DOM) |
| `@remotion/media-utils` | `@motionswift/media-utils` (native audio data) |
| `@remotion/three`, `@react-three/fiber`, `three`, `three/addons/loaders/USDLoader.js` (and the `examples/jsm` and `USDZLoader` paths) | Vendor-graph modules in the shim (`remotion-three.js`, `fiber.js`, `three.js`, `usd-loader.js`): `ThreeCanvas`, `useThree`/`useLoader`, a three.js math subset and USD loader tags. Implemented; see [3D support](three-d.md). Other `three/...` imports fail with `ms/unsupported-package`. |

### Where `node_modules` comes from

| Host | Strategy |
|---|---|
| macOS editor, Linux worker, CI | A normal `bun install` / `npm install` in the project. The resolver reads `node_modules` with Node's resolution algorithm, including the `exports` field and its conditions (`"browser"` → `"import"` → `"default"`). |
| iOS | No package manager on the device. The app ships a **vendor bundle**: React, the shim, and the allowlisted `@remotion/*` packages plus common pure-JS libraries (`zod`, `date-fns`, ...), precompiled in CI. Projects whose imports aren't all in the vendor bundle are compiled on a Mac or in the cloud, and the resulting module graph is synced to the device. |

**Package allowlist:** an import outside the vendor bundle is allowed on macOS and Linux if the package is pure JS. Packages that touch the DOM, Node built-ins (`fs`, `path`, `child_process`), or `window` are reported by lint (`ms/unsupported-package`) and fail at resolve time with the import chain.

## JS runtime environment

JavaScriptCore is a bare engine. The worker supplies this deliberately limited environment:

| Global | Current behavior |
|---|---|
| `console.log/warn/error` | Defined, muted during rendering. Source-mapped logging is planned. |
| `setTimeout`, `clearTimeout`, `setInterval`, `clearInterval`, `queueMicrotask` | Deterministic virtual-time queue, ordered by deadline then registration ID; microtasks settle between host calls. Timers never advance the video frame. Intervals must be cleared before the sample settles. |
| `Promise` | Rejected runtime promises and errors in timer/microtask callbacks fail the current frame. Caught rejections are allowed. Native `async` function promises should be returned to a tracked `.then/.catch` chain or explicitly passed to `cancelRender`; JSC does not expose their unhandled rejections through this shim. |
| `fetch`, `Response`, `Headers`, `AbortController` | Buffered HTTP(S) via URLSession on the render worker, surfaced as a Promise; `text()`, `json()`, `arrayBuffer()` and case-insensitive headers. Text request bodies supported. Pre-aborted signals reject; in-flight abort and streaming are not implemented. Network results are not cached/replayed and must be stable for deterministic renders. |
| `URL`, `URLSearchParams` | Absolute/relative parsing through Foundation, query get/getAll/has/set/append/delete and iteration. URL property setters and the full WHATWG surface are not implemented. |
| `TextEncoder`, `TextDecoder`, `atob`, `btoa` | UTF-8 text and Latin-1 base64. Other decoder encodings/streaming are unsupported. |
| `structuredClone` | JSON-compatible values only; cycles and browser transferable objects are unsupported. |
| `process.env.NODE_ENV` | `production` for render workers. |
| `Math.random`, `Date.now`, `new Date()`, `performance.now` | Seeded random resets each sample; clocks are fixed at zero independently of virtual timer time. |
| `window`, `document`, `requestAnimationFrame`, `Image`, `HTMLCanvasElement` | Not defined; normal JavaScript exceptions include bundle stacks. |

### Async render lifecycle

`delayRender(label?, {timeoutInMilliseconds?})` returns a monotonically unique
worker handle. Every handle must be released exactly once using
`continueRender(handle)`. Unknown, stale and duplicate handles fail the frame.
`cancelRender(error)` fails it immediately at the next lifecycle checkpoint.
The default timeout is 30,000 ms, configurable with
`Runtime(bundle:timeoutInMilliseconds:)` and per-handle options. Diagnostics include
composition ID, frame, handle label and registration stack. A worker also bounds
settling to 10,000 tasks and a wall-time budget; synchronous infinite JS loops
cannot be interrupted by that budget.

The worker flushes React effects, state changes, promises and virtual timers before
committing the native tree. Errors discard retained output; the next sample starts
with clean task, handle and rejection bookkeeping. Switching compositions resets
the same lifecycle state. User module caches and React state also reset every
sample, while vendor code and host output remain retained. User code must not
mutate vendor objects or retain state through custom globals. Cleanup effects run
before reset; handle IDs are never reused so stale callbacks cannot release a new
sample's handles. `calculateMetadata` remains unsupported.

Runtime bundles now use the resettable module-graph loader on both macOS and iOS.
Recompile legacy monolithic bundles; the runtime reports a missing bridge function
if an old bundle is supplied. `make compiler` regenerates both compiler and portable
vendor resources after shim changes.

## Type-level compatibility

The shim package ships `.d.ts` files that **mirror Remotion's public types for the supported subset only**:

- Supported APIs (`interpolate`, `spring`, `Sequence`, `Img`, `OffthreadVideo`, ...) have **the same signatures as Remotion**, so existing code type-checks unchanged.
- Unsupported APIs are **absent**, so `import { IFrame } from 'remotion'` is a compile error with a clear message (via a `@deprecated`-style JSDoc on a `never`-typed stub).
- `style` is narrowed: our package augments `JSX.IntrinsicElements` so `style` is `MotionCSSProperties`, a `csstype` subset. `display: 'grid'` or `position: 'fixed'` then fails **in the editor and in `tsc`**, before lint runs.
- Elements we reject (`canvas`, `iframe`, `table`, ...) are removed from `IntrinsicElements`.
- `type-tests/` in the shim package uses `tsd`/`expect-type` to assert that each supported Remotion signature is assignable both ways to the upstream `remotion` types, for the pinned Remotion version. This catches drift when Remotion is upgraded.

Users opt in with one line in `tsconfig.json`: `"extends": "@motionswift/tsconfig"`. Without it, code still compiles and renders. The type-level check is an extra safety net, and lint remains the gate.

## Published npm packages

| Package | Contents |
|---|---|
| `@motionswift/remotion` | The `remotion` replacement: runtime shim + subset `.d.ts`. |
| `@motionswift/fonts` | `loadFont` implementations, plus a mapping for `@remotion/google-fonts`. |
| `@motionswift/media-utils` | Audio/video metadata helpers backed by the native side. |
| `@motionswift/tsconfig` | Preset: `jsx: react-jsx`, `module: esnext`, `moduleResolution: bundler`, `isolatedModules: true`, `strict: true`, the ES2022 target, and the JSX type augmentation. |
| `@motionswift/eslint-plugin` | The `ms/*` lint rules ([compatibility.md](compatibility.md#lint-rules-jslint)). |
| `@motionswift/cli` | A thin npm wrapper that downloads the platform's `motionswift` binary (the same pattern as `esbuild`), so `npx motionswift render|still|lint|check` works in any project and in CI. |

Versioning: all packages are released together with the engine and share one version. The engine refuses to load a project whose `@motionswift/remotion` major version doesn't match.

## Compatibility checks in a project

```text
npx motionswift check     # = native TypeScript --noEmit (our types) + eslint ms/* + resolve graph + allowlist
npx motionswift still ... # compile (tsgo) + render one frame
npx motionswift render ...
```

`check` emits JSON diagnostics (`{rule, file, line, col, message, fix?}`) so an agent can repair code before rendering.
