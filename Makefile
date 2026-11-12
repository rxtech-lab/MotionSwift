SHELL := /bin/bash
export PATH := $(HOME)/.cargo/bin:$(PATH)
export PKG_CONFIG_PATH := $(CURDIR)/native/pkgconfig:$(PKG_CONFIG_PATH)
.PHONY: lint lint-fix bootstrap compiler native native-ios ios build test visual goldens benchmark showcase ci
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

benchmark: build
	node tests/perf/bench.mjs

showcase: compiler native
	swift run -c release motionswift-showcase

ci: test visual
