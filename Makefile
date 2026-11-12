SHELL := /bin/bash
export PATH := $(HOME)/.cargo/bin:$(PATH)
export PKG_CONFIG_PATH := $(CURDIR)/native/pkgconfig:$(PKG_CONFIG_PATH)
.PHONY: lint lint-fix bootstrap native build test visual goldens benchmark ci
.NOTPARALLEL:

lint:
	swiftlint lint --strict --no-cache --config .swiftlint.yml

lint-fix:
	swiftlint lint --fix --no-cache --config .swiftlint.yml

bootstrap:
	npm ci --prefix tests
	node tests/tools/prepare-browser.mjs
	$(MAKE) native

native:
	./tests/tools/build-native.sh

build: native
	swift build -c release

test: lint build
	swift test
	npm test --prefix tests

visual: build
	node tests/tools/visual.mjs --backend=cpu
	node tests/tools/visual.mjs --backend=gpu

goldens:
	node tests/tools/generate-goldens.mjs

benchmark: build
	node tests/perf/bench.mjs

ci: test visual
