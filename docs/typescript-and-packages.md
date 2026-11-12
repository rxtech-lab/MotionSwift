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

### Where `node_modules` comes from

| Host | Strategy |
|---|---|
| macOS editor, Linux worker, CI | A normal `bun install` / `npm install` in the project. The resolver reads `node_modules` with Node's resolution algorithm, including the `exports` field and its conditions (`"browser"` → `"import"` → `"default"`). |
| iOS | No package manager on the device. The app ships a **vendor bundle**: React, the shim, and the allowlisted `@remotion/*` packages plus common pure-JS libraries (`zod`, `date-fns`, ...), precompiled in CI. Projects whose imports aren't all in the vendor bundle are compiled on a Mac or in the cloud, and the resulting module graph is synced to the device. |

**Package allowlist:** an import outside the vendor bundle is allowed on macOS and Linux if the package is pure JS. Packages that touch the DOM, Node built-ins (`fs`, `path`, `child_process`), or `window` are reported by lint (`ms/unsupported-package`) and fail at resolve time with the import chain.

## JS runtime environment

JavaScriptCore is a bare engine. `MotionRuntime` provides these globals, implemented in Swift:

| Global | Implementation | Notes |
|---|---|---|
| `console.*` | → engine log, with source-mapped locations | |
| `setTimeout`, `clearTimeout`, `setInterval`, `queueMicrotask` | Swift run loop | Needed by `delayRender` patterns. Timers don't advance frames. |
| `fetch`, `Response`, `Headers`, `AbortController` | URLSession / libcurl | For `calculateMetadata` and data loading inside `delayRender`. Responses can be recorded and replayed in CI for determinism. |
| `URL`, `URLSearchParams`, `TextEncoder`, `TextDecoder`, `atob`, `btoa`, `structuredClone` | Swift | |
| `process.env.NODE_ENV` | Inlined at compile time | `production` for renders and `development` in the editor. |
| `Math.random`, `Date.now`, `new Date()`, `performance.now` | Deterministic | See [compatibility.md → Motion determinism](compatibility.md#motion-determinism). |
| `window`, `document`, `requestAnimationFrame`, `Image`, `HTMLCanvasElement` | ❌ not defined | Accessing them throws an error that names the source location. |

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
