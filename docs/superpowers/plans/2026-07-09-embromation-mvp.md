# Embromation MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working macOS menu bar app that translates selected text with a local MLX model, streaming into a floating popup.

**Architecture:** Two units in one repo: `TranslatorCore` (pure Swift Package — prompt building, language detection/resolution, model catalog, settings, translator protocol + fake; fast `swift test`) and the `Embromation` app target (XcodeGen-generated project — menu bar, global hotkey, selection capture, non-activating popup panel, MLX engine, settings UI, onboarding). All UI consumes the core through protocols so the real model never runs in tests.

**Tech Stack:** Swift 5.10 / SwiftUI / AppKit (NSPanel), XcodeGen, XCTest, `ml-explore/mlx-swift-examples` (MLXLLM/MLXLMCommon), `sindresorhus/KeyboardShortcuts`, NaturalLanguage.framework.

**Spec:** `docs/superpowers/specs/2026-07-09-embromation-design.md` (source of truth).

**Out of scope for this plan** (second plan, after MVP works): signed/notarized DMG release workflow, Homebrew cask, Sparkle, custom menu-bar/app icon assets (MVP uses the `character.bubble` SF Symbol), landing page.

**Deviation from spec §3 (deliberate):** MLX-dependent code (`MLXTranslator`, `ModelStore`) lives in the app target (`App/Sources/Engine/`), not in `TranslatorCore`. Reason: `swift test` on the core must stay fast and CI must never compile the MLX C++/Metal stack just to run logic tests. The spec's intent — a testable core behind protocols — is preserved: `StreamingTranslator` lives in core, MLX implements it.

**Deviation from spec §6 (Intel alert):** the binary is arm64-only, so it physically cannot launch on Intel to show an alert — macOS itself explains the incompatibility. The spec's "alert on launch" is superseded by the `ARCHS = arm64` build setting.

## Global Constraints

- macOS 14+ · **Apple Silicon only** — every target builds `ARCHS = arm64`.
- Dependencies frozen: `mlx-swift-examples` + `KeyboardShortcuts`. Nothing else without written justification.
- Privacy invariant: the ONLY network call in the app is the model download from Hugging Face.
- `TranslatorCore` never imports AppKit/SwiftUI (Foundation, Combine, NaturalLanguage allowed).
- Tests NEVER load the real model; CI must pass with no Hugging Face access.
- Concurrency: async/await + actors; no completion handlers.
- User-facing strings in EN and PT-BR (Task 14).
- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`).
- The onboarding demo sentence is exactly **"The book is on the table."** — never change it.
- App is NOT sandboxed (AX API + CGEvent posting require it); hardened runtime stays on.
- Default hotkey: ⌥⌘T. Default language pair: pt-BR ↔ en. Default model: `mlx-community/gemma-3-4b-it-4bit`.

## Prerequisites (once, before Task 1)

```bash
xcode-select -p            # expect /Applications/Xcode.app/... ; else: install Xcode 16+
brew install xcodegen      # project generator
```

---

### Task 1: TranslatorCore package skeleton + Language & Tone types

**Files:**
- Create: `TranslatorCore/Package.swift`
- Create: `TranslatorCore/Sources/TranslatorCore/Language.swift`
- Create: `TranslatorCore/Sources/TranslatorCore/Tone.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/LanguageTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `Language` (`.portuguese/.english/.spanish/.french`, `code: String`, `englishName: String`, `Language.all`), `Tone` (`.neutral/.formal/.casual`, `promptClause: String`). Everything `public`.

- [ ] **Step 1: Create the package manifest**

```swift
// TranslatorCore/Package.swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TranslatorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TranslatorCore", targets: ["TranslatorCore"])
    ],
    targets: [
        .target(name: "TranslatorCore"),
        .testTarget(name: "TranslatorCoreTests", dependencies: ["TranslatorCore"])
    ]
)
```

- [ ] **Step 2: Write the failing test**

```swift
// TranslatorCore/Tests/TranslatorCoreTests/LanguageTests.swift
import XCTest
@testable import TranslatorCore

final class LanguageTests: XCTestCase {
    func testBuiltinLanguagesHaveCodesAndNames() {
        XCTAssertEqual(Language.portuguese.code, "pt")
        XCTAssertEqual(Language.english.code, "en")
        XCTAssertEqual(Language.portuguese.englishName, "Brazilian Portuguese")
        XCTAssertTrue(Language.all.contains(.english))
    }

    func testToneClausesAreNonEmptyAndDistinct() {
        let clauses = Tone.allCases.map(\.promptClause)
        XCTAssertEqual(Set(clauses).count, Tone.allCases.count)
        XCTAssertFalse(clauses.contains(where: \.isEmpty))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `error: cannot find 'Language' in scope`

- [ ] **Step 4: Implement the types**

```swift
// TranslatorCore/Sources/TranslatorCore/Language.swift
public struct Language: Equatable, Hashable, Codable, Sendable {
    /// ISO 639-1 code, matches NLLanguage.rawValue (e.g. "pt", "en").
    public let code: String
    /// English name used inside prompts ("Brazilian Portuguese").
    public let englishName: String

    public init(code: String, englishName: String) {
        self.code = code
        self.englishName = englishName
    }

    public static let portuguese = Language(code: "pt", englishName: "Brazilian Portuguese")
    public static let english = Language(code: "en", englishName: "English")
    public static let spanish = Language(code: "es", englishName: "Spanish")
    public static let french = Language(code: "fr", englishName: "French")
    public static let all: [Language] = [.portuguese, .english, .spanish, .french]
}
```

```swift
// TranslatorCore/Sources/TranslatorCore/Tone.swift
public enum Tone: String, CaseIterable, Codable, Sendable {
    case neutral
    case formal
    case casual

    public var promptClause: String {
        switch self {
        case .neutral: return "Use a neutral, natural tone."
        case .formal: return "Use a formal, professional tone."
        case .casual: return "Use a casual, conversational tone."
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path TranslatorCore`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add TranslatorCore
git commit -m "feat: TranslatorCore package with Language and Tone types"
```

---

### Task 2: PromptBuilder

**Files:**
- Create: `TranslatorCore/Sources/TranslatorCore/PromptBuilder.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/PromptBuilderTests.swift`

**Interfaces:**
- Consumes: `Language`, `Tone` (Task 1).
- Produces: `PromptBuilder.systemPrompt(source:target:tone:customInstructions:glossary:) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
// TranslatorCore/Tests/TranslatorCoreTests/PromptBuilderTests.swift
import XCTest
@testable import TranslatorCore

final class PromptBuilderTests: XCTestCase {
    let builder = PromptBuilder()

    func testMentionsSourceAndTargetLanguages() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("English"))
        XCTAssertTrue(p.contains("Brazilian Portuguese"))
    }

    func testIncludesToneClause() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .formal, customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains(Tone.formal.promptClause))
    }

    func testGlossaryTermsAreListedAndOmittedWhenEmpty() {
        let with = builder.systemPrompt(source: .english, target: .portuguese,
                                        tone: .neutral, customInstructions: "",
                                        glossary: ["deploy", "pipeline"])
        XCTAssertTrue(with.contains("deploy, pipeline"))
        let without = builder.systemPrompt(source: .english, target: .portuguese,
                                           tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertFalse(without.contains("never translate"))
    }

    func testCustomInstructionsAreTrimmedAndIncluded() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "  Keep tech terms.  ",
                                     glossary: [])
        XCTAssertTrue(p.contains("Keep tech terms."))
        XCTAssertFalse(p.contains("  Keep tech terms.  "))
    }

    func testDemandsTranslationOnlyOutput() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("ONLY the translated text"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `error: cannot find 'PromptBuilder' in scope`

- [ ] **Step 3: Implement**

```swift
// TranslatorCore/Sources/TranslatorCore/PromptBuilder.swift
public struct PromptBuilder: Sendable {
    public init() {}

    public func systemPrompt(
        source: Language,
        target: Language,
        tone: Tone,
        customInstructions: String,
        glossary: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("You are a translation engine. Translate the user's message from \(source.englishName) to \(target.englishName).")
        lines.append(tone.promptClause)
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append(custom)
        }
        if !glossary.isEmpty {
            lines.append("Keep these terms exactly as written, never translate them: \(glossary.joined(separator: ", ")).")
        }
        lines.append("Reply with ONLY the translated text. No explanations, no quotes, no notes.")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path TranslatorCore`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TranslatorCore
git commit -m "feat: PromptBuilder with tone, glossary and custom instructions"
```

---

### Task 3: LanguageDetector + LanguagePair + resolver

**Files:**
- Create: `TranslatorCore/Sources/TranslatorCore/LanguageDetector.swift`
- Create: `TranslatorCore/Sources/TranslatorCore/LanguagePair.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/LanguageDetectionTests.swift`

**Interfaces:**
- Consumes: `Language` (Task 1).
- Produces: `LanguageDetector.detect(_ text: String) -> Language?`; `LanguagePair` (`primary`, `secondary`, Codable); `LanguagePairResolver.target(forDetected:pair:) -> Language`.

- [ ] **Step 1: Write the failing tests**

```swift
// TranslatorCore/Tests/TranslatorCoreTests/LanguageDetectionTests.swift
import XCTest
@testable import TranslatorCore

final class LanguageDetectionTests: XCTestCase {
    let detector = LanguageDetector()
    let resolver = LanguagePairResolver()
    let pair = LanguagePair(primary: .portuguese, secondary: .english)

    func testDetectsPortugueseAndEnglish() {
        XCTAssertEqual(detector.detect("Olá, tudo bem com você hoje?")?.code, "pt")
        XCTAssertEqual(detector.detect("The book is on the table.")?.code, "en")
    }

    func testEmptyTextDetectsNil() {
        XCTAssertNil(detector.detect(""))
        XCTAssertNil(detector.detect("   \n"))
    }

    func testResolverFlipsThePair() {
        XCTAssertEqual(resolver.target(forDetected: .portuguese, pair: pair), .english)
        XCTAssertEqual(resolver.target(forDetected: .english, pair: pair), .portuguese)
    }

    func testThirdLanguageAndNilResolveToPrimary() {
        XCTAssertEqual(resolver.target(forDetected: .french, pair: pair), .portuguese)
        XCTAssertEqual(resolver.target(forDetected: nil, pair: pair), .portuguese)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `cannot find 'LanguageDetector' in scope`

- [ ] **Step 3: Implement**

```swift
// TranslatorCore/Sources/TranslatorCore/LanguageDetector.swift
import NaturalLanguage

public struct LanguageDetector: Sendable {
    public init() {}

    public func detect(_ text: String) -> Language? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        if let known = Language.all.first(where: { $0.code == dominant.rawValue }) {
            return known
        }
        let name = Locale(identifier: "en").localizedString(forLanguageCode: dominant.rawValue) ?? dominant.rawValue
        return Language(code: dominant.rawValue, englishName: name)
    }
}
```

```swift
// TranslatorCore/Sources/TranslatorCore/LanguagePair.swift
public struct LanguagePair: Equatable, Codable, Sendable {
    public var primary: Language
    public var secondary: Language

    public init(primary: Language, secondary: Language) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct LanguagePairResolver: Sendable {
    public init() {}

    /// Detected == primary → secondary. Anything else (secondary, third language, nil) → primary.
    public func target(forDetected detected: Language?, pair: LanguagePair) -> Language {
        guard let detected else { return pair.primary }
        return detected == pair.primary ? pair.secondary : pair.primary
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path TranslatorCore`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TranslatorCore
git commit -m "feat: language detection and pair resolution"
```

---

### Task 4: StreamingTranslator protocol, TranslationRequest, FakeTranslator, ModelCatalog

**Files:**
- Create: `TranslatorCore/Sources/TranslatorCore/StreamingTranslator.swift`
- Create: `TranslatorCore/Sources/TranslatorCore/FakeTranslator.swift`
- Create: `TranslatorCore/Sources/TranslatorCore/ModelCatalog.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/TranslatorTests.swift`

**Interfaces:**
- Consumes: `Language`, `Tone` (Task 1).
- Produces:
  - `TranslationRequest` — `text`, `source: Language`, `target: Language`, `tone: Tone`, `customInstructions: String`, `glossary: [String]`.
  - `protocol StreamingTranslator: Sendable { func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> }`
  - `FakeTranslator(canned:wordDelay:)` — streams canned text word by word.
  - `ModelSpec` (`id`, `displayName`, `approxSizeGB: Double`, `minRAMGB: Int`), `ModelCatalog.default`, `ModelCatalog.all`, `ModelCatalog.spec(for:)`.

- [ ] **Step 1: Write the failing tests**

```swift
// TranslatorCore/Tests/TranslatorCoreTests/TranslatorTests.swift
import XCTest
@testable import TranslatorCore

final class TranslatorTests: XCTestCase {
    func testFakeTranslatorStreamsCannedTextInOrder() async throws {
        let fake = FakeTranslator(canned: "O livro está sobre a mesa.")
        let request = TranslationRequest(text: "The book is on the table.",
                                         source: .english, target: .portuguese,
                                         tone: .neutral, customInstructions: "", glossary: [])
        var chunks: [String] = []
        for try await chunk in fake.translate(request) {
            chunks.append(chunk)
        }
        XCTAssertGreaterThan(chunks.count, 1, "must stream in multiple chunks")
        XCTAssertEqual(chunks.joined(), "O livro está sobre a mesa.")
    }

    func testCatalogDefaultIsListedAndUnknownIDFallsBack() {
        XCTAssertTrue(ModelCatalog.all.contains(ModelCatalog.default))
        XCTAssertEqual(ModelCatalog.spec(for: "does/not-exist"), ModelCatalog.default)
        XCTAssertEqual(ModelCatalog.spec(for: ModelCatalog.all[1].id), ModelCatalog.all[1])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `cannot find 'FakeTranslator' in scope`

- [ ] **Step 3: Implement**

```swift
// TranslatorCore/Sources/TranslatorCore/StreamingTranslator.swift
public struct TranslationRequest: Equatable, Sendable {
    public var text: String
    public var source: Language
    public var target: Language
    public var tone: Tone
    public var customInstructions: String
    public var glossary: [String]

    public init(text: String, source: Language, target: Language,
                tone: Tone, customInstructions: String, glossary: [String]) {
        self.text = text
        self.source = source
        self.target = target
        self.tone = tone
        self.customInstructions = customInstructions
        self.glossary = glossary
    }
}

public protocol StreamingTranslator: Sendable {
    /// Yields incremental text chunks; concatenated chunks form the full translation.
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}
```

```swift
// TranslatorCore/Sources/TranslatorCore/FakeTranslator.swift
public struct FakeTranslator: StreamingTranslator {
    public let canned: String
    public let wordDelay: Duration

    public init(canned: String = "O livro está sobre a mesa.", wordDelay: Duration = .zero) {
        self.canned = canned
        self.wordDelay = wordDelay
    }

    public func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let words = canned.split(separator: " ").map(String.init)
        let delay = wordDelay
        return AsyncThrowingStream { continuation in
            Task {
                for (index, word) in words.enumerated() {
                    if delay != .zero { try? await Task.sleep(for: delay) }
                    continuation.yield(index == 0 ? word : " " + word)
                }
                continuation.finish()
            }
        }
    }
}
```

```swift
// TranslatorCore/Sources/TranslatorCore/ModelCatalog.swift
public struct ModelSpec: Equatable, Identifiable, Sendable {
    /// Hugging Face repo id, e.g. "mlx-community/gemma-3-4b-it-4bit".
    public let id: String
    public let displayName: String
    public let approxSizeGB: Double
    public let minRAMGB: Int

    public init(id: String, displayName: String, approxSizeGB: Double, minRAMGB: Int) {
        self.id = id
        self.displayName = displayName
        self.approxSizeGB = approxSizeGB
        self.minRAMGB = minRAMGB
    }
}

public enum ModelCatalog {
    public static let gemma3_4b = ModelSpec(id: "mlx-community/gemma-3-4b-it-4bit",
                                            displayName: "Gemma 3 4B", approxSizeGB: 2.6, minRAMGB: 16)
    public static let qwen3_4b = ModelSpec(id: "mlx-community/Qwen3-4B-4bit",
                                           displayName: "Qwen 3 4B", approxSizeGB: 2.3, minRAMGB: 16)
    public static let qwen25_1_5b = ModelSpec(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                                              displayName: "Qwen 2.5 1.5B (light)", approxSizeGB: 1.0, minRAMGB: 8)
    public static let `default` = gemma3_4b
    public static let all: [ModelSpec] = [gemma3_4b, qwen3_4b, qwen25_1_5b]

    public static func spec(for id: String) -> ModelSpec {
        all.first { $0.id == id } ?? .default
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path TranslatorCore`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TranslatorCore
git commit -m "feat: translator protocol, fake translator and model catalog"
```

---

### Task 5: SettingsStore (persisted app settings)

**Files:**
- Create: `TranslatorCore/Sources/TranslatorCore/SettingsStore.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `LanguagePair`, `Tone`, `ModelCatalog` (Tasks 1–4).
- Produces: `SettingsData` (Codable value with all fields + defaults) and `@MainActor SettingsStore: ObservableObject` with `@Published var data: SettingsData` that auto-persists to injected `UserDefaults`.

- [ ] **Step 1: Write the failing tests**

```swift
// TranslatorCore/Tests/TranslatorCoreTests/SettingsStoreTests.swift
import XCTest
@testable import TranslatorCore

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testDefaultsMatchSpec() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.data.pair, LanguagePair(primary: .portuguese, secondary: .english))
        XCTAssertEqual(store.data.tone, .neutral)
        XCTAssertEqual(store.data.glossary, [])
        XCTAssertEqual(store.data.selectedModelID, ModelCatalog.default.id)
        XCTAssertEqual(store.data.unloadAfterMinutes, 10)
        XCTAssertFalse(store.data.didOnboard)
    }

    @MainActor
    func testMutationsSurviveReload() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.data.tone = .formal
        store.data.glossary = ["deploy", "commit"]
        store.data.didOnboard = true

        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.tone, .formal)
        XCTAssertEqual(reloaded.data.glossary, ["deploy", "commit"])
        XCTAssertTrue(reloaded.data.didOnboard)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `cannot find 'SettingsStore' in scope`

- [ ] **Step 3: Implement**

```swift
// TranslatorCore/Sources/TranslatorCore/SettingsStore.swift
import Foundation
import Combine

public struct SettingsData: Codable, Equatable, Sendable {
    public var pair = LanguagePair(primary: .portuguese, secondary: .english)
    public var tone: Tone = .neutral
    public var customInstructions = ""
    public var glossary: [String] = []
    public var selectedModelID = ModelCatalog.default.id
    public var unloadAfterMinutes = 10
    public var didOnboard = false

    public init() {}
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var data: SettingsData {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let key = "settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            self.data = decoded
        } else {
            self.data = SettingsData()
        }
    }

    private func persist() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        defaults.set(raw, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path TranslatorCore`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add TranslatorCore
git commit -m "feat: persisted settings store with spec defaults"
```

---

### Task 6: App scaffold — XcodeGen project + menu bar app that launches

**Files:**
- Create: `project.yml`
- Create: `Makefile`
- Create: `App/Info.plist`
- Create: `App/Embromation.entitlements`
- Create: `App/Sources/EmbromationApp.swift`
- Create: `App/Sources/AppState.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `FakeTranslator`, `StreamingTranslator` (Tasks 4–5).
- Produces: buildable `Embromation.app` (menu bar only, no Dock icon); `@MainActor AppState` composition root with `settings: SettingsStore` and `translator: StreamingTranslator` (fake for now — swapped in Task 10); `make gen / build / run / test` commands used by every later task.

- [ ] **Step 1: Create project.yml**

```yaml
# project.yml
name: Embromation
options:
  bundleIdPrefix: app.embromation
  deploymentTarget:
    macOS: "14.0"
packages:
  TranslatorCore:
    path: TranslatorCore
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0
targets:
  Embromation:
    type: application
    platform: macOS
    sources:
      - App/Sources
    settings:
      base:
        ARCHS: arm64
        PRODUCT_BUNDLE_IDENTIFIER: app.embromation.Embromation
        INFOPLIST_FILE: App/Info.plist
        CODE_SIGN_ENTITLEMENTS: App/Embromation.entitlements
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_VERSION: 5.10
        MARKETING_VERSION: 0.1.0
        CURRENT_PROJECT_VERSION: 1
    dependencies:
      - package: TranslatorCore
      - package: KeyboardShortcuts
```

Note: the MLX package is added in Task 10, not here — keeps early builds fast.

- [ ] **Step 2: Create Info.plist and entitlements**

```xml
<!-- App/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Embromation</string>
    <key>CFBundleDisplayName</key><string>Embromation</string>
    <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key><string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSMinimumSystemVersion</key><string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 José Augusto da França — MIT License</string>
</dict>
</plist>
```

```xml
<!-- App/Embromation.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

(No sandbox on purpose — AX + CGEvent require it. Hardened runtime is set in build settings.)

- [ ] **Step 3: Create the app entry point and composition root**

```swift
// App/Sources/AppState.swift
import Foundation
import TranslatorCore

@MainActor
final class AppState: ObservableObject {
    let settings = SettingsStore()
    // Swapped for MLXTranslator in Task 10.
    let translator: StreamingTranslator = FakeTranslator(wordDelay: .milliseconds(40))
}
```

```swift
// App/Sources/EmbromationApp.swift
import SwiftUI
import TranslatorCore

@main
struct EmbromationApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            Button("Translate selection") {}
                .disabled(true) // wired in Task 8
            Divider()
            Button("Quit Embromation") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

- [ ] **Step 4: Create the Makefile**

```make
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
```

Also append to `.gitignore`:

```
Embromation.xcodeproj/
.build/
```

- [ ] **Step 5: Build and verify manually**

Run: `make run`
Expected: build succeeds; a speech-bubble icon appears in the menu bar; no Dock icon; menu shows a disabled "Translate selection" and a working "Quit Embromation".

- [ ] **Step 6: Commit**

```bash
git add project.yml Makefile App .gitignore
git commit -m "feat: menu bar app scaffold with XcodeGen"
```

---

### Task 7: SelectionCapture (AX + Cmd+C fallback)

**Files:**
- Create: `App/Sources/Capture/SelectionCapture.swift`
- Modify: `App/Sources/EmbromationApp.swift` (temporary debug menu item)

**Interfaces:**
- Consumes: nothing from core (pure AppKit/ApplicationServices).
- Produces: `protocol SelectionCapturing: Sendable { func captureSelectedText() async -> String? }` and `struct SelectionCapture: SelectionCapturing`. Task 8's coordinator consumes the protocol.

- [ ] **Step 1: Implement capture**

```swift
// App/Sources/Capture/SelectionCapture.swift
import AppKit
import ApplicationServices

protocol SelectionCapturing: Sendable {
    /// Returns the currently selected text in the frontmost app, or nil.
    func captureSelectedText() async -> String?
}

struct SelectionCapture: SelectionCapturing {
    func captureSelectedText() async -> String? {
        if let viaAX = axSelectedText(), !viaAX.isEmpty {
            return viaAX
        }
        return await copyBasedCapture()
    }

    /// Fast path: read kAXSelectedText from the focused UI element. No clipboard involved.
    private func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        let focused = focusedRef as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success else {
            return nil
        }
        return selectedRef as? String
    }

    /// Fallback: simulate ⌘C, poll pasteboard changeCount every 10ms (max 300ms), restore clipboard.
    private func copyBasedCapture() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let startCount = pasteboard.changeCount

        postKeystroke(keyCode: 8, flags: .maskCommand) // 8 = "c"

        var changed = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(10))
            if pasteboard.changeCount != startCount {
                changed = true
                break
            }
        }
        guard changed else { return nil }
        let captured = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }
        return captured
    }

    private func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Add a temporary debug menu item**

In `App/Sources/EmbromationApp.swift`, replace the disabled button with:

```swift
Button("Debug: capture selection") {
    Task {
        let text = await SelectionCapture().captureSelectedText()
        NSLog("[embromation] captured: \(text ?? "<nil>")")
    }
}
```

- [ ] **Step 3: Build and verify manually**

Run: `make run`, grant Accessibility permission when macOS prompts (System Settings → Privacy & Security → Accessibility → enable Embromation).
Then: select text in Safari, click the menu item, and check the log:
`log stream --predicate 'eventMessage CONTAINS "embromation"' --style compact`
Expected: the selected text appears in the log; clipboard content is unchanged afterwards (verify with ⌘V somewhere).
Also verify in a terminal (AX path unavailable → fallback used) that capture still works.

Dev tip: if the permission stops sticking between rebuilds, the ad-hoc signature is changing — open the generated `Embromation.xcodeproj` once in Xcode and let it set your Apple Development team, or add `DEVELOPMENT_TEAM: <your team id>` under `settings.base` in `project.yml`.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "feat: selection capture via AX with Cmd+C polling fallback"
```

---

### Task 8: Popup panel + streaming view + coordinator (fake engine end-to-end)

**Files:**
- Create: `App/Sources/Popup/PopupPanel.swift`
- Create: `App/Sources/Popup/PopupModel.swift`
- Create: `App/Sources/Popup/PopupView.swift`
- Create: `App/Sources/Popup/PopupController.swift`
- Create: `App/Sources/TranslationCoordinator.swift`
- Modify: `App/Sources/AppState.swift`, `App/Sources/EmbromationApp.swift`

**Interfaces:**
- Consumes: `SelectionCapturing` (Task 7), `StreamingTranslator`, `LanguageDetector`, `LanguagePairResolver`, `SettingsStore` (Tasks 3–5).
- Produces: `TranslationCoordinator.translateSelection()` (called by menu + hotkey), `TranslationCoordinator.retarget(_ language: Language)`; `PopupController` with `show()`, `dismiss()`, and state passthroughs; `PopupModel.Phase` enum. Task 9 calls `translateSelection()`; Task 11 adds copy/replace to `PopupView`/`PopupModel`.

- [ ] **Step 1: Popup model**

```swift
// App/Sources/Popup/PopupModel.swift
import Foundation
import TranslatorCore

@MainActor
final class PopupModel: ObservableObject {
    enum Phase: Equatable {
        case working            // capturing / preparing model
        case noSelection
        case permissionNeeded
        case streaming
        case done
        case failed(String)
    }

    @Published var phase: Phase = .working
    @Published var text = ""
    @Published var sourceCode = ""
    @Published var target: Language = .portuguese

    // Wired by the coordinator / controller:
    var onRetarget: ((Language) -> Void)?
    var onCopy: (() -> Void)?      // implemented in Task 11
    var onReplace: (() -> Void)?   // implemented in Task 11
    var onRetry: (() -> Void)?
}
```

- [ ] **Step 2: Non-activating panel**

```swift
// App/Sources/Popup/PopupPanel.swift
import AppKit

/// Floating panel that never steals focus from the host app.
final class PopupPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                   styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                   backing: .buffered, defer: false)
        self.contentView = contentView
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: Popup view**

```swift
// App/Sources/Popup/PopupView.swift
import SwiftUI
import TranslatorCore

struct PopupView: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            Divider()
            footer
        }
        .frame(width: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private var header: some View {
        HStack {
            Text("\(model.sourceCode.uppercased()) → \(model.target.code.uppercased())")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.tint.opacity(0.15)))
            Spacer()
            Text("local model")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Translating…").foregroundStyle(.secondary)
            }
        case .noSelection:
            Text("No text selected — select something and press the shortcut again. Tip: if the app blocks capture, copy the text (⌘C) and retry.")
                .foregroundStyle(.secondary)
        case .permissionNeeded:
            VStack(alignment: .leading, spacing: 8) {
                Text("Accessibility permission is required to capture selected text.")
                Button("Open System Settings…") {
                    NSWorkspace.shared.open(URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        case .streaming, .done:
            ScrollView {
                Text(model.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                Button("Try again") { model.onRetry?() }
                Text("If this keeps happening, try the lighter model in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Copy") { model.onCopy?() }
                .disabled(model.phase != .done)
            Button("Replace") { model.onReplace?() }
                .disabled(model.phase != .done)
            Picker("", selection: Binding(
                get: { model.target },
                set: { model.onRetarget?($0) }
            )) {
                ForEach(Language.all, id: \.code) { lang in
                    Text(lang.englishName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            Spacer()
            Text("esc closes").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
```

- [ ] **Step 4: Popup controller (positioning + dismissal monitors)**

```swift
// App/Sources/Popup/PopupController.swift
import AppKit
import SwiftUI

@MainActor
final class PopupController {
    let model = PopupModel()
    private var panel: PopupPanel?
    private var monitors: [Any] = []
    var onDismiss: (() -> Void)?

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: PopupView(model: model))
            panel = PopupPanel(contentView: hosting)
        }
        position()
        panel?.orderFrontRegardless()
        installMonitors()
    }

    func dismiss() {
        removeMonitors()
        panel?.orderOut(nil)
        onDismiss?()
    }

    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - 40, y: mouse.y - panel.frame.height - 16)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    /// Esc anywhere or a click outside the panel dismisses it.
    /// Global monitors require the Accessibility permission we already hold.
    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        } { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // esc
                Task { @MainActor in self?.dismiss() }
            }
        } { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
```

- [ ] **Step 5: Coordinator (the pipeline)**

```swift
// App/Sources/TranslationCoordinator.swift
import AppKit
import TranslatorCore

@MainActor
final class TranslationCoordinator {
    private let settings: SettingsStore
    private let capture: SelectionCapturing
    private let translator: StreamingTranslator
    private let popup: PopupController
    private var currentTask: Task<Void, Never>?
    private var lastCapturedText = ""

    init(settings: SettingsStore, capture: SelectionCapturing,
         translator: StreamingTranslator, popup: PopupController) {
        self.settings = settings
        self.capture = capture
        self.translator = translator
        self.popup = popup
        popup.onDismiss = { [weak self] in self?.currentTask?.cancel() }
        popup.model.onRetarget = { [weak self] lang in self?.retarget(lang) }
        popup.model.onRetry = { [weak self] in self?.translateSelection() }
    }

    func translateSelection() {
        currentTask?.cancel()
        currentTask = Task { await run() }
    }

    func retarget(_ language: Language) {
        guard !lastCapturedText.isEmpty else { return }
        currentTask?.cancel()
        let text = lastCapturedText
        currentTask = Task { await stream(text: text, forcedTarget: language) }
    }

    private func run() async {
        popup.model.phase = .working
        popup.model.text = ""
        popup.show()

        guard AXIsProcessTrusted() else {
            popup.model.phase = .permissionNeeded
            return
        }
        var text = await capture.captureSelectedText() ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Spec §6: when capture fails (app blocks AX and ⌘C), fall back to the
            // clipboard so "copy manually, press the shortcut again" works.
            text = NSPasteboard.general.string(forType: .string) ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            popup.model.phase = .noSelection
            return
        }
        lastCapturedText = text
        await stream(text: text, forcedTarget: nil)
    }

    private func stream(text: String, forcedTarget: Language?) async {
        let detected = LanguageDetector().detect(text)
        let target = forcedTarget
            ?? LanguagePairResolver().target(forDetected: detected, pair: settings.data.pair)
        let source = detected ?? settings.data.pair.secondary

        popup.model.sourceCode = source.code
        popup.model.target = target
        popup.model.text = ""
        popup.model.phase = .streaming

        let request = TranslationRequest(text: text, source: source, target: target,
                                         tone: settings.data.tone,
                                         customInstructions: settings.data.customInstructions,
                                         glossary: settings.data.glossary)
        do {
            for try await chunk in translator.translate(request) {
                try Task.checkCancellation()
                popup.model.text += chunk
            }
            popup.model.phase = .done
        } catch is CancellationError {
            // dismissed or superseded — nothing to do
        } catch {
            popup.model.phase = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 6: Wire into AppState and the menu**

Replace `App/Sources/AppState.swift` with:

```swift
// App/Sources/AppState.swift
import Foundation
import TranslatorCore

@MainActor
final class AppState: ObservableObject {
    let settings = SettingsStore()
    let popup = PopupController()
    // Swapped for MLXTranslator in Task 10.
    let translator: StreamingTranslator = FakeTranslator(wordDelay: .milliseconds(40))
    lazy var coordinator = TranslationCoordinator(settings: settings,
                                                  capture: SelectionCapture(),
                                                  translator: translator,
                                                  popup: popup)
}
```

In `App/Sources/EmbromationApp.swift`, replace the debug menu item with:

```swift
Button("Translate selection") { state.coordinator.translateSelection() }
```

- [ ] **Step 7: Build and verify manually**

Run: `make run`
Expected: select text anywhere → menu item → popup appears near the cursor, fake translation ("O livro está sobre a mesa.") streams word by word, focus stays in the original app, Esc and click-outside dismiss, no selection shows the "No text selected" state.

- [ ] **Step 8: Commit**

```bash
git add App
git commit -m "feat: streaming popup with translation pipeline (fake engine)"
```

---

### Task 9: Global hotkey

**Files:**
- Create: `App/Sources/HotkeyController.swift`
- Modify: `App/Sources/AppState.swift`, `App/Sources/EmbromationApp.swift`

**Interfaces:**
- Consumes: `TranslationCoordinator.translateSelection()` (Task 8), KeyboardShortcuts package (declared in Task 6).
- Produces: `KeyboardShortcuts.Name.translateSelection` (default ⌥⌘T) — Task 12's settings UI renders a recorder for this same name.

- [ ] **Step 1: Implement**

```swift
// App/Sources/HotkeyController.swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection",
                                         default: .init(.t, modifiers: [.option, .command]))
}

@MainActor
final class HotkeyController {
    init(onTrigger: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) {
            onTrigger()
        }
    }
}
```

In `App/Sources/AppState.swift` add the property and start hook:

```swift
    private var hotkey: HotkeyController?

    func start() {
        guard hotkey == nil else { return } // idempotent: scenePhase fires repeatedly
        hotkey = HotkeyController { [weak self] in
            self?.coordinator.translateSelection()
        }
    }
```

In `App/Sources/EmbromationApp.swift` call it once from the scene:

```swift
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            // ... existing items ...
        }
        .onChange(of: scenePhase, initial: true) { _, _ in state.start() }
```

Add `@Environment(\.scenePhase) private var scenePhase` to the struct.

- [ ] **Step 2: Build and verify manually**

Run: `make run`
Expected: select text in any app, press ⌥⌘T → popup streams the fake translation. Works with the menu closed.

- [ ] **Step 3: Commit**

```bash
git add App
git commit -m "feat: global hotkey (⌥⌘T) triggers translation"
```

---

### Task 10: Real engine — ModelStore + MLXTranslator

**Files:**
- Modify: `project.yml` (add MLX package)
- Create: `App/Sources/Engine/ModelStore.swift`
- Create: `App/Sources/Engine/MLXTranslator.swift`
- Modify: `App/Sources/AppState.swift`

**Interfaces:**
- Consumes: `StreamingTranslator`, `TranslationRequest`, `PromptBuilder`, `ModelCatalog` (Tasks 2–4), `SettingsStore` (Task 5).
- Produces: `@MainActor ModelStore: ObservableObject` with `enum State { unknown, missing, downloading(Double), ready }`, `func refresh()`, `func download() async`, `var state: State`, `var lastErrorMessage: String?` — Tasks 12–13 bind UI to it. `MLXTranslator: StreamingTranslator` (actor) that lazily loads, streams, and unloads after idle.

**API-drift note (not a placeholder — a maintenance reality):** the code below targets the `mlx-swift-examples` API as of its 2025 line (`LLMModelFactory.loadContainer`, `ModelContainer.perform`, `MLXLMCommon.generate` returning an async sequence of `.chunk` values, `Chat.Message`). If the pinned revision differs, open `Applications/LLMEval/` in the mlx-swift-examples checkout (SPM cache: `.build/DerivedData/SourcePackages/checkouts/mlx-swift-examples/`) and match its exact calls — the shape (prepare input via processor → iterate generated chunks) is stable across versions.

- [ ] **Step 1: Add the MLX package to project.yml**

Under `packages:` add:

```yaml
  MLXExamples:
    url: https://github.com/ml-explore/mlx-swift-examples
    branch: main
```

Under the target's `dependencies:` add:

```yaml
      - package: MLXExamples
        product: MLXLLM
```

After the first successful build, pin it: note the resolved revision from `Embromation.xcodeproj` → `Package.resolved` (find it with `find .build -name Package.resolved`) and replace `branch: main` with `revision: <hash>` in `project.yml`. Commit that pin.

- [ ] **Step 2: ModelStore**

```swift
// App/Sources/Engine/ModelStore.swift
import Foundation
import Hub
import MLXLMCommon
import MLXLLM
import TranslatorCore

@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable {
        case unknown
        case missing
        case downloading(Double) // 0.0 ... 1.0
        case ready
    }

    @Published var state: State = .unknown
    @Published var lastErrorMessage: String?

    private let settings: SettingsStore

    /// All model files live under Application Support, never in the repo.
    static let hub = HubApi(downloadBase: URL.applicationSupportDirectory
        .appending(path: "Embromation/models"))

    init(settings: SettingsStore) {
        self.settings = settings
        refresh()
    }

    var selectedSpec: ModelSpec { ModelCatalog.spec(for: settings.data.selectedModelID) }

    func refresh() {
        state = isDownloaded(selectedSpec) ? .ready : .missing
    }

    func isDownloaded(_ spec: ModelSpec) -> Bool {
        let dir = Self.hub.localRepoLocation(Hub.Repo(id: spec.id))
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    /// Downloads (and warms) the selected model. Progress is published for the UI.
    func download() async {
        state = .downloading(0)
        lastErrorMessage = nil
        do {
            _ = try await LLMModelFactory.shared.loadContainer(
                hub: Self.hub,
                configuration: ModelConfiguration(id: selectedSpec.id)
            ) { progress in
                Task { @MainActor in
                    self.state = .downloading(progress.fractionCompleted)
                }
            }
            state = .ready
        } catch {
            lastErrorMessage = error.localizedDescription
            state = .missing
        }
    }
}
```

- [ ] **Step 3: MLXTranslator**

```swift
// App/Sources/Engine/MLXTranslator.swift
import Foundation
import MLXLMCommon
import MLXLLM
import TranslatorCore

/// Loads the model lazily, keeps it resident, unloads after an idle period.
actor MLXTranslator: StreamingTranslator {
    private let modelID: @Sendable () -> String
    private let unloadAfterMinutes: @Sendable () -> Int
    private var container: ModelContainer?
    private var containerModelID: String?
    private var idleEpoch = 0

    init(modelID: @escaping @Sendable () -> String,
         unloadAfterMinutes: @escaping @Sendable () -> Int) {
        self.modelID = modelID
        self.unloadAfterMinutes = unloadAfterMinutes
    }

    nonisolated func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: TranslationRequest,
                     yield: @escaping @Sendable (String) -> Void) async throws {
        let container = try await loadedContainer()
        let system = PromptBuilder().systemPrompt(source: request.source,
                                                  target: request.target,
                                                  tone: request.tone,
                                                  customInstructions: request.customInstructions,
                                                  glossary: request.glossary)
        try await container.perform { (context: ModelContext) in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [.system(system), .user(request.text)]))
            let parameters = GenerateParameters(maxTokens: 2048, temperature: 0.3)
            let stream = try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
            for await generation in stream {
                try Task.checkCancellation()
                if case .chunk(let text) = generation {
                    yield(text)
                }
            }
        }
        scheduleIdleUnload()
    }

    private func loadedContainer() async throws -> ModelContainer {
        let id = modelID()
        if let container, containerModelID == id { return container }
        container = nil // release old model before loading a different one
        let loaded = try await LLMModelFactory.shared.loadContainer(
            hub: ModelStore.hub,
            configuration: ModelConfiguration(id: id)
        ) { _ in }
        container = loaded
        containerModelID = id
        return loaded
    }

    /// Frees ~2.5GB of RAM after the configured idle period (spec §4.2).
    private func scheduleIdleUnload() {
        idleEpoch += 1
        let epoch = idleEpoch
        let minutes = max(1, unloadAfterMinutes())
        Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            await self.unloadIfIdle(since: epoch)
        }
    }

    private func unloadIfIdle(since epoch: Int) {
        guard epoch == idleEpoch else { return }
        container = nil
        containerModelID = nil
    }
}
```

- [ ] **Step 4: Swap the fake for the real engine**

The actor reads settings off the main actor, so the closures read the persisted
`SettingsData` directly from `UserDefaults` (thread-safe) instead of touching
the `@MainActor` store. Add a tiny helper to `TranslatorCore`:

```swift
// Append to TranslatorCore/Sources/TranslatorCore/SettingsStore.swift
public extension SettingsData {
    /// Thread-safe snapshot of persisted settings, for non-main-actor readers.
    static func snapshot(from defaults: UserDefaults = .standard) -> SettingsData {
        guard let raw = defaults.data(forKey: "settings.v1"),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) else {
            return SettingsData()
        }
        return decoded
    }
}
```

Then replace the `translator` property in `App/Sources/AppState.swift`:

```swift
    lazy var modelStore = ModelStore(settings: settings)
    lazy var translator: StreamingTranslator = MLXTranslator(
        modelID: { SettingsData.snapshot().selectedModelID },
        unloadAfterMinutes: { SettingsData.snapshot().unloadAfterMinutes }
    )
```

- [ ] **Step 5: Verify core tests still pass and the app builds**

Run: `make test && make build`
Expected: tests PASS (they never touch MLX); build succeeds (first MLX compile takes several minutes).

- [ ] **Step 6: Manual end-to-end with the real model**

Run: `make run`. First translation triggers a model download (~2.6GB — watch progress in Activity Monitor network tab; the onboarding UI for this arrives in Task 13). Then: select an English sentence, ⌥⌘T.
Expected: real Portuguese translation streams into the popup; a second translation starts in <1s (model resident).

- [ ] **Step 7: Pin the MLX revision (per Step 1) and commit**

```bash
git add project.yml App
git commit -m "feat: real MLX engine with lazy load and idle unload"
```

---

### Task 11: Popup actions — copy, replace, cancel-on-dismiss

**Files:**
- Create: `App/Sources/Capture/SelectionReplacer.swift`
- Modify: `App/Sources/TranslationCoordinator.swift`

**Interfaces:**
- Consumes: `PopupModel.onCopy/onReplace` hooks (Task 8).
- Produces: `SelectionReplacer.replaceSelection(with:) async` — pastes over the original selection and restores the clipboard.

- [ ] **Step 1: Implement the replacer**

```swift
// App/Sources/Capture/SelectionReplacer.swift
import AppKit

struct SelectionReplacer {
    /// Puts `text` on the clipboard, simulates ⌘V into the still-focused app,
    /// then restores the previous clipboard content.
    func replaceSelection(with text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postKeystroke(keyCode: 9, flags: .maskCommand) // 9 = "v"
        try? await Task.sleep(for: .milliseconds(250))  // let the app consume the paste

        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }
    }

    private func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Wire copy and replace in the coordinator**

Add to `TranslationCoordinator.init`, after the existing hooks:

```swift
        popup.model.onCopy = { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(self.popup.model.text, forType: .string)
            self.popup.dismiss()
        }
        popup.model.onReplace = { [weak self] in
            guard let self else { return }
            let translation = self.popup.model.text
            self.popup.dismiss()
            Task { await SelectionReplacer().replaceSelection(with: translation) }
        }
```

- [ ] **Step 3: Build and verify manually**

Run: `make run`
Expected: translate a selection in TextEdit → "Replace" pastes the translation over the original text and the previous clipboard survives (⌘V elsewhere confirms); "Copy" puts the translation on the clipboard and closes the popup; changing the language in the popup picker re-runs the translation to that target once.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "feat: copy and replace-selection actions in the popup"
```

---

### Task 12: Settings window

**Files:**
- Create: `App/Sources/Settings/SettingsView.swift`
- Modify: `App/Sources/EmbromationApp.swift`

**Interfaces:**
- Consumes: `SettingsStore` (Task 5), `ModelStore` (Task 10), `KeyboardShortcuts.Name.translateSelection` (Task 9), `Language.all`, `Tone.allCases`, `ModelCatalog.all`.
- Produces: `SettingsView(settings:modelStore:)` shown via SwiftUI `Settings` scene.

- [ ] **Step 1: Implement the settings form**

```swift
// App/Sources/Settings/SettingsView.swift
import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import TranslatorCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore
    @State private var newTerm = ""

    var body: some View {
        Form {
            Section("Languages") {
                Picker("Primary", selection: $settings.data.pair.primary) {
                    ForEach(Language.all, id: \.code) { Text($0.englishName).tag($0) }
                }
                Picker("Secondary", selection: $settings.data.pair.secondary) {
                    ForEach(Language.all, id: \.code) { Text($0.englishName).tag($0) }
                }
                Text("The detected language is translated to the other side of the pair.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Translation") {
                Picker("Tone", selection: $settings.data.tone) {
                    ForEach(Tone.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Extra instructions", text: $settings.data.customInstructions, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Never translate these terms") {
                ForEach(settings.data.glossary, id: \.self) { term in
                    HStack {
                        Text(term).font(.body.monospaced())
                        Spacer()
                        Button(role: .destructive) {
                            settings.data.glossary.removeAll { $0 == term }
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add term", text: $newTerm)
                        .onSubmit(addTerm)
                    Button("Add", action: addTerm)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Translate selection", name: .translateSelection)
            }

            Section("Model") {
                Picker("Model", selection: $settings.data.selectedModelID) {
                    ForEach(ModelCatalog.all) { spec in
                        Text("\(spec.displayName) — \(spec.approxSizeGB, specifier: "%.1f") GB")
                            .tag(spec.id)
                    }
                }
                .onChange(of: settings.data.selectedModelID) { modelStore.refresh() }

                switch modelStore.state {
                case .ready:
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .downloading(let fraction):
                    ProgressView(value: fraction) { Text("Downloading…") }
                case .missing, .unknown:
                    Button("Download model") { Task { await modelStore.download() } }
                }
                if let message = modelStore.lastErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }

                Stepper("Unload from RAM after \(settings.data.unloadAfterMinutes) min idle",
                        value: $settings.data.unloadAfterMinutes, in: 1...60)
            }

            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Spec §4.7 "iniciar no login" — backed by SMAppService (macOS 13+).
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("[embromation] launch-at-login failed: \(error)")
                }
            }
        )
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !settings.data.glossary.contains(term) else { return }
        settings.data.glossary.append(term)
        newTerm = ""
    }
}
```

- [ ] **Step 2: Add the Settings scene and menu item**

In `App/Sources/EmbromationApp.swift`, inside `var body: some Scene` add a second scene after the `MenuBarExtra`:

```swift
        Settings {
            SettingsView(settings: state.settings, modelStore: state.modelStore)
        }
```

And in the menu, above the Quit button:

```swift
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
```

- [ ] **Step 3: Build and verify manually**

Run: `make run`
Expected: menu → Settings… opens the form; every change persists across app relaunches (check tone + glossary); recording a new shortcut works immediately; glossary terms survive and are honored in the next translation ("deploy" stays "deploy").

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "feat: settings window with languages, tone, glossary, shortcut and model"
```

---

### Task 13: Onboarding (welcome → permission → download → demo)

**Files:**
- Create: `App/Sources/Onboarding/OnboardingView.swift`
- Modify: `App/Sources/EmbromationApp.swift`, `App/Sources/AppState.swift`

**Interfaces:**
- Consumes: `SettingsStore.data.didOnboard` (Task 5), `ModelStore` (Task 10), `AppState.translator` (Task 10).
- Produces: onboarding window shown on first launch; sets `didOnboard = true` at the end.

- [ ] **Step 1: Implement the onboarding view**

```swift
// App/Sources/Onboarding/OnboardingView.swift
import SwiftUI
import ApplicationServices
import TranslatorCore

struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore
    let translator: StreamingTranslator
    let dismiss: () -> Void

    @State private var step = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var demoText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Load-bearing joke — see AGENTS.md. Never change this sentence.
    private static let demoSentence = "The book is on the table."

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch step {
                case 0: welcome
                case 1: permission
                case 2: download
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ForEach(0..<4) { index in
                    Circle().fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
                Spacer()
                Button(step == 3 ? "Start using" : "Continue", action: advance)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            }
        }
        .padding(28)
        .frame(width: 460, height: 360)
        .onReceive(timer) { _ in accessibilityGranted = AXIsProcessTrusted() }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return accessibilityGranted
        case 2: return modelStore.state == .ready
        default: return true
        }
    }

    private func advance() {
        if step == 3 {
            settings.data.didOnboard = true
            dismiss()
            return
        }
        step += 1
        if step == 1 {
            // Triggers the system prompt that lists the app in Accessibility settings.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        if step == 2, modelStore.state != .ready {
            Task { await modelStore.download() }
        }
        if step == 3 {
            runDemo()
        }
    }

    private func runDemo() {
        demoText = ""
        let request = TranslationRequest(text: Self.demoSentence,
                                         source: .english, target: settings.data.pair.primary,
                                         tone: .neutral, customInstructions: "", glossary: [])
        Task {
            do {
                for try await chunk in translator.translate(request) { demoText += chunk }
            } catch {
                demoText = "…" // demo is best-effort; real errors surface in normal use
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Image(systemName: "character.bubble").font(.system(size: 44))
            Text("Chega de embromation").font(.title2.bold())
            Text("Select text in any app, press the shortcut, and watch the translation appear instantly. Nothing leaves your Mac — no account, no API keys.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private var permission: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 40))
            Text("Accessibility permission").font(.title3.bold())
            Text("macOS requires this permission so Embromation can read the text you select in other apps. It is used for nothing else.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open System Settings…") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            if accessibilityGranted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private var download: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 40))
            Text("Downloading the model").font(.title3.bold())
            Text("\(modelStore.selectedSpec.displayName) runs entirely on your Mac. One-time download.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if case .downloading(let fraction) = modelStore.state {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))% of ~\(modelStore.selectedSpec.approxSizeGB, specifier: "%.1f") GB")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if modelStore.state == .ready {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let message = modelStore.lastErrorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Try again") { Task { await modelStore.download() } }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal").font(.system(size: 40))
            Text("All set").font(.title3.bold())
            Text("“\(Self.demoSentence)”").italic()
            Text(demoText.isEmpty ? "…" : demoText).bold()
            Text("Select any text and press ⌥⌘T.").foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Show it on first launch**

Add to `AppState`:

```swift
    var needsOnboarding: Bool { !settings.data.didOnboard }
```

In `App/Sources/EmbromationApp.swift` add a `Window` scene after `Settings`:

```swift
        Window("Welcome to Embromation", id: "onboarding") {
            OnboardingView(settings: state.settings,
                           modelStore: state.modelStore,
                           translator: state.translator) {
                NSApp.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
```

And open it from `start()` in `AppState` — inject an opener closure from the App via `@Environment(\.openWindow)`. Concretely: in `EmbromationApp`, add `@Environment(\.openWindow) private var openWindow` and change the `.onChange` handler to:

```swift
        .onChange(of: scenePhase, initial: true) { _, _ in
            state.start()
            if state.needsOnboarding { openWindow(id: "onboarding") }
        }
```

- [ ] **Step 3: Build and verify manually**

Reset first: `defaults delete app.embromation.Embromation` then `make run`.
Expected: onboarding opens; step 2 auto-detects the permission grant (green check appears without clicking anything in the app); step 3 shows real download progress; final step translates "The book is on the table." with the real model; relaunching the app does NOT show onboarding again.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "feat: three-step onboarding with permission check and model download"
```

---

### Task 14: Localization (EN + PT-BR)

**Files:**
- Create: `App/Resources/en.lproj/Localizable.strings`
- Create: `App/Resources/pt-BR.lproj/Localizable.strings`
- Modify: `project.yml` (add resources), all `App/Sources/**/*.swift` user-facing strings

**Interfaces:**
- Consumes: every user-facing string from Tasks 6–13.
- Produces: `L10n.t(_ key: String)` helper; the app renders in PT-BR when macOS language is Portuguese.

- [ ] **Step 1: Add resources to project.yml**

Change the target's `sources:` to:

```yaml
    sources:
      - App/Sources
      - App/Resources
```

(XcodeGen detects `.lproj` directories under a plain source path and adds them as localized resources — do NOT use a `type: folder` reference, folder references don't localize.)

- [ ] **Step 2: Create the string tables**

```
/* App/Resources/en.lproj/Localizable.strings */
"menu.translate" = "Translate selection";
"menu.settings" = "Settings…";
"menu.quit" = "Quit Embromation";
"popup.working" = "Translating…";
"popup.no_selection" = "No text selected — select something and press the shortcut again. Tip: if the app blocks capture, copy the text (⌘C) and retry.";
"popup.permission" = "Accessibility permission is required to capture selected text.";
"popup.open_settings" = "Open System Settings…";
"popup.copy" = "Copy";
"popup.replace" = "Replace";
"popup.retry" = "Try again";
"popup.esc" = "esc closes";
"popup.local_model" = "local model";
"onboarding.title" = "Chega de embromation";
"onboarding.welcome_body" = "Select text in any app, press the shortcut, and watch the translation appear instantly. Nothing leaves your Mac — no account, no API keys.";
"onboarding.permission_title" = "Accessibility permission";
"onboarding.permission_body" = "macOS requires this permission so Embromation can read the text you select in other apps. It is used for nothing else.";
"onboarding.download_title" = "Downloading the model";
"onboarding.ready" = "All set";
"onboarding.hint" = "Select any text and press ⌥⌘T.";
"onboarding.continue" = "Continue";
"onboarding.start" = "Start using";
"settings.languages" = "Languages";
"settings.translation" = "Translation";
"settings.glossary" = "Never translate these terms";
"settings.shortcut" = "Shortcut";
"settings.model" = "Model";
"settings.download" = "Download model";
"settings.downloaded" = "Downloaded";
```

```
/* App/Resources/pt-BR.lproj/Localizable.strings */
"menu.translate" = "Traduzir seleção";
"menu.settings" = "Ajustes…";
"menu.quit" = "Sair do Embromation";
"popup.working" = "Traduzindo…";
"popup.no_selection" = "Nenhum texto selecionado — selecione algo e aperte o atalho de novo. Dica: se o app bloquear a captura, copie o texto (⌘C) e tente de novo.";
"popup.permission" = "A permissão de Acessibilidade é necessária para capturar o texto selecionado.";
"popup.open_settings" = "Abrir Ajustes do Sistema…";
"popup.copy" = "Copiar";
"popup.replace" = "Substituir";
"popup.retry" = "Tentar de novo";
"popup.esc" = "esc fecha";
"popup.local_model" = "modelo local";
"onboarding.title" = "Chega de embromation";
"onboarding.welcome_body" = "Selecione um texto em qualquer app, aperte o atalho e veja a tradução na hora. Nada sai do seu Mac — sem conta, sem API key.";
"onboarding.permission_title" = "Permissão de Acessibilidade";
"onboarding.permission_body" = "O macOS exige essa permissão para o Embromation ler o texto que você seleciona em outros apps. Ela não é usada para mais nada.";
"onboarding.download_title" = "Baixando o modelo";
"onboarding.ready" = "Tudo pronto";
"onboarding.hint" = "Selecione qualquer texto e aperte ⌥⌘T.";
"onboarding.continue" = "Continuar";
"onboarding.start" = "Começar a usar";
"settings.languages" = "Idiomas";
"settings.translation" = "Tradução";
"settings.glossary" = "Nunca traduzir estes termos";
"settings.shortcut" = "Atalho";
"settings.model" = "Modelo";
"settings.download" = "Baixar modelo";
"settings.downloaded" = "Baixado";
```

- [ ] **Step 3: Add the helper and sweep the views**

```swift
// App/Sources/L10n.swift
import Foundation

enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
```

Replace every hardcoded user-facing string in `EmbromationApp.swift`, `PopupView.swift`, `OnboardingView.swift`, `SettingsView.swift` with `L10n.t("...")` calls using the keys above (e.g. `Button(L10n.t("popup.copy"))`). Strings that are data, log messages, or the demo sentence stay as-is.

- [ ] **Step 4: Build and verify manually**

Run: `make run` with system language English → English UI. Then:
`defaults write app.embromation.Embromation AppleLanguages '("pt-BR")'` and relaunch → PT-BR UI.
Cleanup: `defaults delete app.embromation.Embromation AppleLanguages`.

- [ ] **Step 5: Commit**

```bash
git add App project.yml
git commit -m "feat: EN and PT-BR localization"
```

---

### Task 15: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `make`-equivalent commands from Task 6.
- Produces: green CI on every push — core tests + app build, no model download, no signing.

- [ ] **Step 1: Create the workflow**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  core-tests:
    name: TranslatorCore tests
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: swift test --package-path TranslatorCore

  app-build:
    name: App build (arm64, unsigned)
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Generate project
        run: xcodegen generate
      - name: Build
        run: |
          xcodebuild -project Embromation.xcodeproj -scheme Embromation \
            -configuration Release CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Push and verify**

Run: `git add .github && git commit -m "ci: core tests and app build on push" && git push`
Then: `gh run watch` (or `gh run list --limit 1`)
Expected: both jobs green. The app-build job takes ~15 min on first run (MLX compile); later runs benefit from Apple's toolchain cache only — acceptable for now.

- [ ] **Step 3: Commit** (already committed in Step 2)

---

## Verification checklist (manual, after all tasks — commit as `docs/manual-test-checklist.md` if desired)

1. Hotkey works from: Safari, Chrome, VS Code, Slack, TextEdit, Terminal (fallback path).
2. Clipboard survives capture AND replace (copy something first, translate, paste — original content intact).
3. EN→PT and PT→EN both work with one hotkey; Spanish text goes to Portuguese.
4. Glossary: add "deploy"; translate "We need to deploy the new version." → "deploy" untouched.
5. Formal vs casual tone produce visibly different Portuguese.
6. Popup: Esc closes, click-outside closes, focus never leaves the source app.
7. Second translation within 10 min starts streaming in <1s; after idle unload, first one shows a load pause.
8. Onboarding appears exactly once; demo sentence is "The book is on the table."
9. Kill network (Wi-Fi off): translations still work with a downloaded model.
10. `swift test --package-path TranslatorCore` passes offline.
