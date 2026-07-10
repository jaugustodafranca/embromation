# Makefile
.PHONY: gen test build run

DERIVED := .build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Embromation.app

gen:
	xcodegen generate

test:
	swift test --package-path TranslatorCore

build: gen
	# -skipMacroValidation: mlx-swift-lm's MLXHuggingFace target uses a Swift macro
	# (#hubDownloader / #huggingFaceTokenizerLoader) that Xcode otherwise refuses to
	# run without an interactive "Trust & Enable" prompt, which headless CI can't answer.
	xcodebuild -project Embromation.xcodeproj -scheme Embromation \
		-configuration Debug -derivedDataPath $(DERIVED) -skipMacroValidation build

run: build
	open $(APP)
