# Makefile
.PHONY: gen test build run

DERIVED := .build/DerivedData
# Release by default: the Debug configuration compiles the MLX C++ stack with
# optimizations off and generates tokens at about a third of the speed, so a
# Debug build is only useful for debugging (`make CONFIG=Debug run`).
CONFIG ?= Release
APP := $(DERIVED)/Build/Products/$(CONFIG)/Embromation.app

gen:
	xcodegen generate

test:
	swift test --package-path TranslatorCore

build: gen
	# -skipMacroValidation / -skipPackagePluginValidation: mlx-swift-lm ships a Swift
	# macro (#hubDownloader / #huggingFaceTokenizerLoader) and mlx-swift a build plugin
	# (CudaBuild) that Xcode otherwise refuses to run without an interactive
	# "Trust & Enable" prompt, which headless builds can't answer.
	xcodebuild -project Embromation.xcodeproj -scheme Embromation \
		-configuration $(CONFIG) -derivedDataPath $(DERIVED) \
		-skipMacroValidation -skipPackagePluginValidation build

run: build
	open $(APP)
