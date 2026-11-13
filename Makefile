SHELL := /bin/bash
export PATH := $(HOME)/.cargo/bin:$(PATH)
export PKG_CONFIG_PATH := $(CURDIR)/native/pkgconfig:$(PKG_CONFIG_PATH)
.PHONY: lint lint-fix bootstrap compiler native native-ios ios build test visual goldens benchmark runtime-benchmark showcase ci three-visual three-goldens three-benchmark maps-visual
.NOTPARALLEL:

lint:
	swiftlint lint --strict --no-cache --config .swiftlint.yml

lint-fix:
	swiftlint lint --fix --no-cache --config .swiftlint.yml

tests/node_modules/.package-lock.json: tests/package.json tests/package-lock.json
	npm ci --prefix tests
	@touch $@

compiler: tests/node_modules/.package-lock.json
	node tests/tools/package-compiler.mjs
	node tests/tools/package-portable.mjs

bootstrap: compiler native
	node tests/tools/prepare-browser.mjs

native:
	./tests/tools/build-native.sh

native-ios:
	./tests/tools/build-native.sh --ios

# iOS/iPadOS: device and simulator builds of the MotionStudio example app (no signing).
ios: compiler native-ios
	./tests/tools/build-ios.sh

build: compiler native
	swift build -c release

test: lint build
	swift test --no-parallel
	npm test --prefix tests

visual: build
	node tests/tools/visual.mjs --backend=cpu
	node tests/tools/visual.mjs --backend=gpu

goldens:
	node tests/tools/generate-goldens.mjs

# 3D: native Metal ThreeCanvas stills vs Remotion three.js references (CPU and GPU compositing).
three-visual: build
	node tests/tools/three-visual.mjs --backend=cpu
	node tests/tools/three-visual.mjs --backend=gpu

three-goldens:
	node tests/tools/three-goldens.mjs

# 3D: Remotion vs native video timings at 360p and 1080p with SSIM parity and a minimum speedup.
three-benchmark: build
	node tests/perf/three.mjs

benchmark: build
	node tests/perf/bench.mjs

runtime-benchmark: compiler native
	node tests/perf/runtime.mjs

showcase: compiler native
	swift run -c release motionswift-showcase

# Standalone Apple Silicon .app, with local ad-hoc signing. Release CI replaces the signature.
.PHONY: showcase-app
showcase-app: compiler native
	bash scripts/package-showcase.sh "$${VERSION:-0.0.0}" "$${BUILD_NUMBER:-1}"

maps-visual: build
	node tests/tools/maps-visual.mjs
	node tests/tools/maps-visual.mjs --railway

ci: test visual three-visual maps-visual
