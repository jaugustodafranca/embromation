# Makefile
.PHONY: gen test build run

DERIVED := .build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Embromation.app

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
		-configuration Debug -derivedDataPath $(DERIVED) \
		-skipMacroValidation -skipPackagePluginValidation build

run: build
	open $(APP)
