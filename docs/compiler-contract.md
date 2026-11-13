# Compiler contract and reproduction

MotionSwift keeps the delivered compiler paths: macOS uses bundled **tsgo 7.0.2**
for ES2022 emission/type checking and **esbuild 0.28.1** for linking. Portable
compilation uses **Sucrase 3.35.1** and Babel parsing inside JavaScriptCore.
Neither path starts Node at application runtime. Node is a build dependency for
`make compiler`, which regenerates the bundled compiler, inspector and vendor resources.

## Cache identity and invalidation

Each compiler instance owns a bounded, in-memory cache. SHA-256 identities include
source bytes, source paths, entry, compiler/resource versions, resolver settings
and stamping mode. Portable graph identities include the complete supplied source
and configuration manifest (a conservative superset of the dependency graph).
A changed/deleted source, config or added alias candidate invalidates that graph.
On a graph miss, up to 256 pure module transforms are reused; imports are resolved
again against current files so changed dependency edges cannot survive a hit.
Graph caches retain up to eight results. Native graph identities include non-hidden project
source/config/package bytes, vendor hash, inspector hash and fixed compiler options;
esbuild's external input files and their ancestor package manifests are rehashed
before returning a hit. Type checks are deliberately uncached.

`cacheStatistics` exposes hits/misses: portable values describe modules in the last
compile; native values count graph requests since initialization or `clearCache()`.
A portable graph hit reports every module as a hit. Cache state does not enter graph
serialization, emitted code, maps or source stamps. Cold native extraction paths are
removed from source maps; whitespace minification removes generated path comments.
No persistent disk cache or cross-process coordination is claimed.

## Sources, diagnostics and editor stamps

Module graphs retain optional Source Map v3 JSON in `Module.sourceMap`; old format-1
graphs without maps still decode. Sources and `sourcesContent` refer to original
project TS/TSX/JS. tsgo maps feed esbuild; Sucrase token maps have inserted editor
stamp columns removed. `data-ms-src` always uses original one-based file:line:column,
including multiple elements on one line. Stamping is enabled on portable graphs;
Mac graphs remain `stamped: false` and carry original maps. Linking records each module's generated
line offset and installs a stack mapper before evaluating project code. Runtime
exceptions map `motionswift:bundle:line:column` frames to original sources; unmapped
vendor frames remain available. Synthetic generated tokens map to the nearest
preceding original token, rather than promising character-level attribution.
Compiler syntax/subset errors and portable unresolved imports use original sources.
TypeScript diagnostics come from original sources, separately from rendering.

## Resolution

Both paths honor `baseUrl`, exact `paths`, longest wildcard prefix precedence and
ordered target fallbacks. Exact aliases beat wildcards; pinned vendor specifiers
beat user aliases. Relative tsconfig `extends` (including extensionless `.json`)
and JSONC comments/trailing commas are supported. Inherited alias targets retain
the defining config's base directory. `@motionswift/tsconfig` is the built-in preset;
other package-based `extends` fail with a migration hint rather than being ignored.
Only resolution settings are imported; MotionSwift's target, JSX, strictness and
subset remain fixed. Declaration files are never executable candidates.

Portable resolution substitutes `.ts`/`.tsx`/`.jsx` before `.js`, `.mts` before
`.mjs`, and `.cts` before `.cjs`, and supports extensionless and directory-index
imports. Portable devices do not load arbitrary `node_modules`: unresolved packages
report an original import location and a Mac/cloud graph sync hint.

macOS delegates package `exports` (root/subpath/wildcard/arrays/blocked paths) to
esbuild's browser resolver. Active conditions include `browser`, `import` and
`default`; condition objects are evaluated in package declaration order, as with
Node/esbuild, not a reordered browser/import/default priority list. Fallback legacy
fields are `browser,module,main`. User aliases point at tsgo's emitted tree, while
npm packages resolve from the project's `node_modules`. Node builtins and remaining
external non-vendor requires remain unsupported.

## Rust SWC C ABI decision

The original Phase 1 requirement for a Rust SWC compiler exposed through a C ABI
is **not implemented**. This work explicitly supersedes that architecture for the
current release: retain native tsgo/esbuild on macOS and the shipped in-process
JavaScriptCore portable compiler. Adding a third compiler would duplicate syntax,
map and diagnostics behavior without removing either delivered path. Rust remains
active for the Skia graphics C ABI; that is not a compiler ABI. A future Rust SWC
integration requires a separate compatibility decision and parity fixtures before
it can replace either compiler. Linux compiler integration, portable type checking
and full decorator parity are outside this contract.

## Reproduce

```sh
make compiler
swift test --no-parallel --filter 'portableContentCache|portableAliases|portableMaps|portableImportDiagnostics|portableDependencyErrors|nativeCompilerCache|nativeExports|nativeRequires'
swift test --no-parallel
npm test --prefix tests
```

The focused fixtures execute native bundled binaries or JavaScriptCore, with no
Node subprocess. They check cold/warm byte equality, dependency changes/deletion,
stamp settings, alias precedence/fallbacks, package exports and original mapped
errors. Build-time resource packaging and the separate npm suite do use Node.
For example, a throw on line 3 of `main.ts` reports `main.ts:3:…` through tsgo,
esbuild, graph serialization and linking. A stamped portable throw on line 1 of
`src/view.tsx` maps the generated `Error` token to `src/view.tsx:1:49`, without attributing the inserted stamp text
to the user. Cache measurements are printed by the focused cache fixtures.

A local Apple Silicon focused run on 2026-11-13 measured the two-module portable
fixture at 7.07 ms cold / 0.19 ms warm (2 hits, 0 misses), and the native
alias/package fixture at 770 ms cold / 0.82 ms warm (1 graph hit, 1 prior miss).
These are single-run fixture measurements, not large-project throughput claims.
