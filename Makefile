# Makefile
DERIVED := .build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Embromation.app

gen:
	xcodegen generate

test:
	swift test --package-path TranslatorCore

build: gen
	xcodebuild -project Embromation.xcodeproj -scheme Embromation \
		-configuration Debug -derivedDataPath $(DERIVED) build

run: build
	open $(APP)
