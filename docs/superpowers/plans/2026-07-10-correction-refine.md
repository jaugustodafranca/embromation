# Correction + Refine Implementation Plan (Feature 2 → v1.0.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Fix-grammar action (⌃G), a configurable popup-vs-direct-replace flow, a feedback→regenerate loop in the popup, new default shortcuts (⌃T/⌃G), and the download-UX debt fixes — completing v1.0.0.

**Architecture:** Extends the existing pipeline; no new subsystems. `TranslationMode` and `Refinement` ride on `TranslationRequest`; `PromptBuilder` gains a correction prompt; `MLXTranslator` builds a multi-turn chat when refining. The coordinator grows `correctSelection()`/`refine(_:)` and a no-popup direct path. UI: feedback field in the popup, Correction section in Settings, menu items with shortcut hints, honest download progress with cancel.

**Spec:** `docs/superpowers/specs/2026-07-10-correction-and-refine-design.md` (source of truth).
**Branch:** `feat/correction-refine` (already exists, spec committed).

## Global Constraints

- All MVP hard rules hold (AGENTS.md): core UI-free, privacy invariant, tests never load the model, EN+PT-BR strings with key parity, conventional commits, deps frozen.
- New default shortcuts: translate **⌃T** (`.init(.t, modifiers: [.control])`), fix grammar **⌃G** (`.init(.g, modifiers: [.control])`). The old ⌥⌘T default is replaced everywhere it is displayed (onboarding hint).
- **Settings migration safety:** adding fields to `SettingsData` must NOT reset existing users' settings — synthesized Codable fails on missing keys, so Task 2 introduces tolerant decoding. This is load-bearing.
- Existing behavior is regression-protected: translation flow, popup shortcuts (⌘C/⌘⏎ gated on `.done`), clipboard gate, think-filter all stay as-is.
- Verification per task: `make test` (core) and, for app tasks, `make build` + launch smoke (`open` + `pgrep` + `pkill`). GUI behavior is human-verified at the end (author QA).

---

### Task 1: Core — TranslationMode, Refinement, correction prompt, fake echo

**Files:**
- Modify: `TranslatorCore/Sources/TranslatorCore/StreamingTranslator.swift`
- Modify: `TranslatorCore/Sources/TranslatorCore/PromptBuilder.swift`
- Modify: `TranslatorCore/Sources/TranslatorCore/FakeTranslator.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/CorrectionTests.swift` (new)

**Interfaces:**
- Consumes: existing `Language`, `Tone`, request/protocol types.
- Produces: `TranslationMode` (`.translate/.correct`), `Refinement(previousOutput:feedback:)`, `TranslationRequest.mode` (default `.translate`) and `.refinement` (default nil), `PromptBuilder.correctionPrompt(language:tone:customInstructions:glossary:) -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
// TranslatorCore/Tests/TranslatorCoreTests/CorrectionTests.swift
import XCTest
@testable import TranslatorCore

final class CorrectionTests: XCTestCase {
    let builder = PromptBuilder()

    func testRequestDefaultsKeepBackwardCompatibility() {
        let request = TranslationRequest(text: "Oi", source: .portuguese, target: .english,
                                         tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertEqual(request.mode, .translate)
        XCTAssertNil(request.refinement)
    }

    func testCorrectionPromptKeepsSameLanguageAndDemandsCorrectedTextOnly() {
        let p = builder.correctionPrompt(language: .portuguese, tone: .neutral,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("proofreading"))
        XCTAssertTrue(p.contains("same language"))
        XCTAssertTrue(p.contains("Brazilian Portuguese"))
        XCTAssertTrue(p.contains("Preserve emoji"))
        XCTAssertTrue(p.contains("ONLY the corrected text"))
    }

    func testCorrectionPromptCarriesToneCustomAndGlossary() {
        let p = builder.correctionPrompt(language: .english, tone: .casual,
                                         customInstructions: "Keep it short.",
                                         glossary: ["deploy"])
        XCTAssertTrue(p.contains(Tone.casual.promptClause))
        XCTAssertTrue(p.contains("Keep it short."))
        XCTAssertTrue(p.contains("deploy"))
    }

    func testTranslationPromptUnchangedRegression() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("translation engine"))
        XCTAssertTrue(p.contains("ONLY the translated text"))
    }

    func testFakeTranslatorEchoesFeedbackWhenRefining() async throws {
        let fake = FakeTranslator(canned: "Texto corrigido.")
        var request = TranslationRequest(text: "texto", source: .portuguese, target: .portuguese,
                                         tone: .neutral, customInstructions: "", glossary: [])
        request.mode = .correct
        request.refinement = Refinement(previousOutput: "Texto corrigido.", feedback: "mais casual")
        var output = ""
        for try await chunk in fake.translate(request) { output += chunk }
        XCTAssertTrue(output.contains("Texto corrigido."))
        XCTAssertTrue(output.contains("mais casual"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `cannot find 'Refinement' in scope`, `has no member 'mode'`, `has no member 'correctionPrompt'`

- [ ] **Step 3: Implement**

In `StreamingTranslator.swift`, add above `TranslationRequest`:

```swift
public enum TranslationMode: Equatable, Sendable {
    /// Translate from `source` to `target`.
    case translate
    /// Fix grammar/spelling/punctuation keeping the same language and meaning.
    case correct
}

public struct Refinement: Equatable, Sendable {
    public var previousOutput: String
    public var feedback: String

    public init(previousOutput: String, feedback: String) {
        self.previousOutput = previousOutput
        self.feedback = feedback
    }
}
```

In `TranslationRequest`, add the two stored properties and extend the init with
defaulted parameters (existing call sites stay valid):

```swift
    public var mode: TranslationMode
    public var refinement: Refinement?

    public init(text: String, source: Language, target: Language,
                tone: Tone, customInstructions: String, glossary: [String],
                mode: TranslationMode = .translate, refinement: Refinement? = nil) {
        self.text = text
        self.source = source
        self.target = target
        self.tone = tone
        self.customInstructions = customInstructions
        self.glossary = glossary
        self.mode = mode
        self.refinement = refinement
    }
```

In `PromptBuilder.swift`, add:

```swift
    public func correctionPrompt(
        language: Language,
        tone: Tone,
        customInstructions: String,
        glossary: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("You are a proofreading engine. Fix grammar, spelling and punctuation of the user's message, keeping the same language (\(language.englishName)), meaning and tone.")
        lines.append("Preserve emoji, keyboard shortcuts (like ⌃T), code, URLs, numbers and any other symbols exactly as written — never drop or translate them.")
        lines.append(tone.promptClause)
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append(custom)
        }
        if !glossary.isEmpty {
            lines.append("Keep these terms exactly as written, never translate them: \(glossary.joined(separator: ", ")).")
        }
        lines.append("Reply with ONLY the corrected text. No explanations, no quotes, no notes.")
        return lines.joined(separator: "\n")
    }
```

In `FakeTranslator.swift`, make the canned text echo refinement feedback —
replace the first line of `translate` body:

```swift
    public func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let text = request.refinement.map { "\(canned) [\($0.feedback)]" } ?? canned
        let words = text.split(separator: " ").map(String.init)
        // (rest unchanged)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path TranslatorCore`
Expected: PASS (26 tests)

- [ ] **Step 5: Commit**

```bash
git add TranslatorCore
git commit -m "feat: translation mode, refinement and correction prompt in core"
```

---

### Task 2: Core — correction flow setting with migration-safe decoding

**Files:**
- Modify: `TranslatorCore/Sources/TranslatorCore/SettingsStore.swift`
- Test: `TranslatorCore/Tests/TranslatorCoreTests/SettingsStoreTests.swift` (extend)

**Interfaces:**
- Produces: `SettingsData.correctionReplacesDirectly: Bool` (default `false`); tolerant decoding so blobs persisted by older versions keep every other value.

- [ ] **Step 1: Write the failing tests** (append to SettingsStoreTests)

```swift
    @MainActor
    func testCorrectionFlowDefaultsToPopup() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.data.correctionReplacesDirectly)
    }

    func testDecodingOldBlobWithoutNewKeysKeepsExistingValues() throws {
        // Blob shape persisted by the MVP (no correctionReplacesDirectly key).
        let old = """
        {"pair":{"primary":{"code":"pt","englishName":"Brazilian Portuguese"},"secondary":{"code":"en","englishName":"English"}},"tone":"formal","customInstructions":"tech","glossary":["deploy"],"selectedModelID":"mlx-community/Qwen3-4B-4bit","unloadAfterMinutes":5,"didOnboard":true}
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.tone, .formal)
        XCTAssertEqual(decoded.glossary, ["deploy"])
        XCTAssertEqual(decoded.unloadAfterMinutes, 5)
        XCTAssertTrue(decoded.didOnboard)
        XCTAssertFalse(decoded.correctionReplacesDirectly)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path TranslatorCore`
Expected: FAIL — `has no member 'correctionReplacesDirectly'`

- [ ] **Step 3: Implement**

In `SettingsData`, add the field and a tolerant decoder (encode stays
synthesized). Replace the struct body's property list and add:

```swift
    public var correctionReplacesDirectly = false
```

and below `public init() {}`:

```swift
    private enum CodingKeys: String, CodingKey {
        case pair, tone, customInstructions, glossary,
             selectedModelID, unloadAfterMinutes, didOnboard,
             correctionReplacesDirectly
    }

    /// Tolerant decoding: any missing key falls back to its default so adding
    /// fields never resets a user's persisted settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SettingsData()
        pair = try c.decodeIfPresent(LanguagePair.self, forKey: .pair) ?? defaults.pair
        tone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? defaults.tone
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions) ?? defaults.customInstructions
        glossary = try c.decodeIfPresent([String].self, forKey: .glossary) ?? defaults.glossary
        selectedModelID = try c.decodeIfPresent(String.self, forKey: .selectedModelID) ?? defaults.selectedModelID
        unloadAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .unloadAfterMinutes) ?? defaults.unloadAfterMinutes
        didOnboard = try c.decodeIfPresent(Bool.self, forKey: .didOnboard) ?? defaults.didOnboard
        correctionReplacesDirectly = try c.decodeIfPresent(Bool.self, forKey: .correctionReplacesDirectly) ?? defaults.correctionReplacesDirectly
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path TranslatorCore`
Expected: PASS (28 tests)

- [ ] **Step 5: Commit**

```bash
git add TranslatorCore
git commit -m "feat: correction flow setting with migration-safe decoding"
```

---

### Task 3: Engine — mode-aware prompt and refinement chat

**Files:**
- Modify: `App/Sources/Engine/MLXTranslator.swift`

**Interfaces:**
- Consumes: `TranslationMode`, `Refinement`, `PromptBuilder.correctionPrompt` (Tasks 1–2).
- Produces: engine honors `request.mode` and `request.refinement`. No signature changes.

- [ ] **Step 1: Implement**

In `run(_:yield:)`, replace the `let system = ...` statement with:

```swift
        let builder = PromptBuilder()
        let system: String
        switch request.mode {
        case .translate:
            system = builder.systemPrompt(source: request.source,
                                          target: request.target,
                                          tone: request.tone,
                                          customInstructions: request.customInstructions,
                                          glossary: request.glossary)
        case .correct:
            system = builder.correctionPrompt(language: request.source,
                                              tone: request.tone,
                                              customInstructions: request.customInstructions,
                                              glossary: request.glossary)
        }
```

and replace the `UserInput(chat: ...)` construction with:

```swift
            var chat: [Chat.Message] = [.system(system), .user(request.text)]
            if let refinement = request.refinement {
                chat.append(.assistant(refinement.previousOutput))
                chat.append(.user("Feedback: \(refinement.feedback). Produce an improved version. Reply with ONLY the new text, in the same language as before."))
            }
            let input = try await context.processor.prepare(
                input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
```

(Keep the existing `GenerateParameters`, generation loop, `ThinkBlockFilter`, and idle-unload untouched.)

- [ ] **Step 2: Verify**

Run: `make test` (28 green — engine has no core impact) and `make build` (BUILD SUCCEEDED).

- [ ] **Step 3: Commit**

```bash
git add App
git commit -m "feat: engine builds correction prompts and refinement chat history"
```

---

### Task 4: Coordinator, hotkeys (⌃T/⌃G) and menu

**Files:**
- Modify: `App/Sources/TranslationCoordinator.swift`
- Modify: `App/Sources/HotkeyController.swift`
- Modify: `App/Sources/AppState.swift`
- Modify: `App/Sources/EmbromationApp.swift`
- Modify: `App/Sources/Popup/PopupModel.swift` (add `isCorrection` + `onRefine`)
- Modify: both `Localizable.strings` (menu key)

**Interfaces:**
- Produces: `TranslationCoordinator.correctSelection()`, `refine(_ feedback: String)`; `KeyboardShortcuts.Name.fixGrammar` (default ⌃G); translate default becomes ⌃T; menu shows both items with shortcut hints; `PopupModel.isCorrection`, `PopupModel.onRefine` (UI consumes in Task 5).

- [ ] **Step 1: HotkeyController**

Replace the file body:

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection",
                                         default: .init(.t, modifiers: [.control]))
    static let fixGrammar = Self("fixGrammar",
                                 default: .init(.g, modifiers: [.control]))
}

@MainActor
final class HotkeyController {
    init(onTranslate: @escaping @MainActor () -> Void,
         onCorrect: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) { onTranslate() }
        KeyboardShortcuts.onKeyUp(for: .fixGrammar) { onCorrect() }
    }
}
```

- [ ] **Step 2: AppState.start()**

```swift
    func start() {
        guard hotkey == nil else { return } // idempotent: scenePhase fires repeatedly
        hotkey = HotkeyController(
            onTranslate: { [weak self] in self?.coordinator.translateSelection() },
            onCorrect: { [weak self] in self?.coordinator.correctSelection() }
        )
    }
```

- [ ] **Step 3: Menu (EmbromationApp)**

```swift
            Button(L10n.t("menu.translate")) { state.coordinator.translateSelection() }
                .keyboardShortcut("t", modifiers: [.control])
            Button(L10n.t("menu.fix_grammar")) { state.coordinator.correctSelection() }
                .keyboardShortcut("g", modifiers: [.control])
```

Strings (both tables): `"menu.fix_grammar"` = EN `"Fix grammar"` / PT-BR `"Corrigir texto"`.

- [ ] **Step 4: PopupModel additions**

```swift
    @Published var isCorrection = false
    var onRefine: ((String) -> Void)?
```

- [ ] **Step 5: Coordinator**

Rework `TranslationCoordinator`:

1. `translateSelection()` → `currentTask = Task { await run(mode: .translate) }`; add:

```swift
    func correctSelection() {
        currentTask?.cancel()
        currentTask = Task { await run(mode: .correct) }
    }

    func refine(_ feedback: String) {
        guard var request = lastRequest, popup.model.phase == .done else { return }
        request.refinement = Refinement(previousOutput: popup.model.text, feedback: feedback)
        currentTask?.cancel()
        let req = request
        currentTask = Task { await stream(req) }
    }
```

2. Add fields `private var lastRequest: TranslationRequest?` and wire
   `popup.model.onRefine = { [weak self] feedback in self?.refine(feedback) }`
   in `init` next to the other hooks.

3. Change `run()` to `run(mode: TranslationMode)`. After the capture/clipboard
   gate produces `text` (all existing logic untouched), build:

```swift
        let detected = LanguageDetector().detect(text)
        let direct = mode == .correct && settings.data.correctionReplacesDirectly
        let source: Language
        let target: Language
        switch mode {
        case .translate:
            target = LanguagePairResolver().target(forDetected: detected, pair: settings.data.pair)
            source = detected ?? settings.data.pair.secondary
        case .correct:
            source = detected ?? settings.data.pair.primary
            target = source
        }
        let request = TranslationRequest(text: text, source: source, target: target,
                                         tone: settings.data.tone,
                                         customInstructions: settings.data.customInstructions,
                                         glossary: settings.data.glossary,
                                         mode: mode)
        if direct {
            await directCorrect(request)
        } else {
            await stream(request)
        }
```

   IMPORTANT: in direct mode the popup must NOT be shown while capturing —
   move the existing `popup.show()/phase = .working` prologue behind
   `if !(mode == .correct && settings.data.correctionReplacesDirectly)`.
   The Accessibility guard shows the popup in BOTH modes (errors always
   surface).

4. Refactor `stream(text:forcedTarget:)` into `stream(_ request: TranslationRequest)`
   storing `lastRequest = request` at the top and setting
   `popup.model.isCorrection = (request.mode == .correct)`. `retarget(_:)`
   rebuilds a fresh `.translate` request from `lastCapturedText` (clears
   refinement by construction). Existing cancellation guards, first-chunk
   phase flip, and empty-response guard stay.

5. Add:

```swift
    private func directCorrect(_ request: TranslationRequest) async {
        var result = ""
        do {
            for try await chunk in translator.translate(request) {
                try Task.checkCancellation()
                result += chunk
            }
        } catch is CancellationError {
            return
        } catch {
            popup.model.isCorrection = true
            popup.model.phase = .failed(error.localizedDescription)
            popup.show()
            return
        }
        guard !Task.isCancelled else { return }
        let corrected = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else {
            popup.model.isCorrection = true
            popup.model.phase = .failed(L10n.t("popup.empty_response"))
            popup.show()
            return
        }
        lastRequest = request
        await SelectionReplacer().replaceSelection(with: corrected)
    }
```

- [ ] **Step 6: Verify**

`make test` (28) + `make build` + launch smoke (`open`, `pgrep`, `pkill`).

- [ ] **Step 7: Commit**

```bash
git add App
git commit -m "feat: fix-grammar action with ⌃T/⌃G defaults, direct-replace mode and refine plumbing"
```

---

### Task 5: Popup — feedback field, key behavior, correction chip

**Files:**
- Modify: `App/Sources/Popup/PopupView.swift`
- Modify: `App/Sources/Popup/PopupPanel.swift`
- Modify: both `Localizable.strings`

**Interfaces:**
- Consumes: `PopupModel.isCorrection`, `onRefine` (Task 4).
- Produces: feedback UI; panel accepts typing only in the field.

- [ ] **Step 1: PopupPanel key behavior**

Change `override var canBecomeKey: Bool { false }` to `{ true }` (keep
`canBecomeMain` false and `becomesKeyOnlyIfNeeded = true` — the panel only
becomes key when a text field asks for it; buttons/hotkeys still never steal
focus from the host app).

- [ ] **Step 2: PopupView**

Add `@State private var feedbackText = ""`. In `header`, render the chip as a
single language when correcting:

```swift
            if !model.sourceCode.isEmpty {
                Text(model.isCorrection
                     ? model.sourceCode.uppercased()
                     : "\(model.sourceCode.uppercased()) → \(model.target.code.uppercased())")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.tint.opacity(0.15)))
            }
```

Hide the target picker when correcting: wrap the existing `Picker` in
`if !model.isCorrection { ... }`.

Below `content` (inside the outer VStack, before the footer divider), add the
feedback row shown only when done:

```swift
            if hasFinishedTranslation {
                Divider()
                HStack(spacing: 8) {
                    TextField(L10n.t("popup.feedback_placeholder"), text: $feedbackText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(submitFeedback)
                    Button(L10n.t("popup.refine"), action: submitFeedback)
                        .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
```

with:

```swift
    private func submitFeedback() {
        let feedback = feedbackText.trimmingCharacters(in: .whitespaces)
        guard !feedback.isEmpty else { return }
        feedbackText = ""
        model.onRefine?(feedback)
    }
```

Also clear stale feedback text when a new run starts:
`.onChange(of: model.phase) { _, phase in if phase == .working { feedbackText = "" } }`
on the outer VStack.

- [ ] **Step 3: Strings (both tables)**

```
"popup.feedback_placeholder" = EN "Tell the model what to improve…" / PT-BR "Diga ao modelo o que melhorar…";
"popup.refine" = EN "Regenerate" / PT-BR "Regenerar";
```

- [ ] **Step 4: Verify** — `make test`, `make build`, launch smoke.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "feat: feedback-and-regenerate loop in the popup"
```

---

### Task 6: Settings section, onboarding copy, welcome-guide menu item

**Files:**
- Modify: `App/Sources/Settings/SettingsView.swift`
- Modify: `App/Sources/EmbromationApp.swift`
- Modify: both `Localizable.strings`

- [ ] **Step 1: Settings — Correction section** (after the Shortcut section)

```swift
            Section(L10n.t("settings.correction")) {
                KeyboardShortcuts.Recorder(L10n.t("settings.fix_grammar"), name: .fixGrammar)
                Picker(L10n.t("settings.correction_flow"), selection: $settings.data.correctionReplacesDirectly) {
                    Text(L10n.t("settings.correction_popup")).tag(false)
                    Text(L10n.t("settings.correction_direct")).tag(true)
                }
                Text(L10n.t("settings.correction_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }
```

Rename the existing Shortcut section's recorder label to the translate-specific
key (`settings.translate_shortcut`) so the two recorders read as siblings.

- [ ] **Step 2: Welcome-guide menu item** (EmbromationApp, above Settings…)

```swift
            Button(L10n.t("menu.welcome_guide")) { openWindow(id: "onboarding") }
```

- [ ] **Step 3: Onboarding hint string update** (tables only — the view already
uses the key): change `onboarding.hint` to
EN `"Select any text and press ⌃T to translate — or ⌃G to fix grammar."` /
PT-BR `"Selecione qualquer texto e aperte ⌃T para traduzir — ou ⌃G para corrigir."`

- [ ] **Step 4: Strings (both tables)**

```
"menu.welcome_guide" = EN "Welcome guide" / PT-BR "Guia de boas-vindas";
"settings.correction" = EN "Correction" / PT-BR "Correção";
"settings.fix_grammar" = EN "Fix grammar" / PT-BR "Corrigir texto";
"settings.translate_shortcut" = EN "Translate selection" / PT-BR "Traduzir seleção";
"settings.correction_flow" = EN "After correcting" / PT-BR "Depois de corrigir";
"settings.correction_popup" = EN "Show popup" / PT-BR "Mostrar popup";
"settings.correction_direct" = EN "Replace directly" / PT-BR "Substituir direto";
"settings.correction_hint" = EN "Replace directly pastes the corrected text over your selection without showing the popup. Errors always open the popup." / PT-BR "Substituir direto cola o texto corrigido por cima da seleção sem mostrar o popup. Erros sempre abrem o popup.";
```

- [ ] **Step 5: Verify** — `make test`, `make build`, launch smoke, plus key-parity check:
`grep -c '^"' App/Resources/en.lproj/Localizable.strings App/Resources/pt-BR.lproj/Localizable.strings` (equal counts).

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: correction settings, welcome-guide menu item and ⌃T/⌃G onboarding copy"
```

---

### Task 7: Honest download progress with cancel

**Files:**
- Modify: `App/Sources/Engine/ModelStore.swift`
- Modify: `App/Sources/Onboarding/OnboardingView.swift`
- Modify: `App/Sources/Settings/SettingsView.swift`
- Modify: both `Localizable.strings`

**Context:** the loader's progress callback reports ~0% for the entire
download (file-count based), so the % display lies. Replace with an honest
indeterminate bar + a Cancel action; a cancelled/stalled download must always
leave a retry path.

- [ ] **Step 1: ModelStore — cancellable download**

Add `private var downloadTask: Task<Void, Never>?` and:

```swift
    func download() {
        guard case .downloading = state else {
            state = .downloading(0)
            lastErrorMessage = nil
            downloadTask = Task { await performDownload() }
            return
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        refresh()
    }

    private func performDownload() async {
        do {
            _ = try await LLMModelFactory.shared.loadContainer(
                /* keep existing downloader/tokenizer/config arguments */
            ) { progress in
                Task { @MainActor in
                    if case .downloading = self.state {
                        self.state = .downloading(progress.fractionCompleted)
                    }
                }
            }
            refresh()
        } catch is CancellationError {
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
            state = .missing
        }
    }
```

Callers change from `await modelStore.download()` to `modelStore.download()`
(OnboardingView `startDownloadIfNeeded`/retry button, SettingsView download
button — remove the `Task { await ... }` wrappers).

- [ ] **Step 2: Onboarding download step UI**

Replace the `.downloading` branch:

```swift
            if case .downloading = modelStore.state {
                ProgressView()
                Text(String(format: L10n.t("onboarding.downloading_size"), modelStore.selectedSpec.approxSizeGB))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.t("onboarding.cancel_download")) { modelStore.cancelDownload() }
            }
```

(Indeterminate spinner — no fake percentage.)

- [ ] **Step 3: Settings model section** — same treatment: `.downloading` case
shows `ProgressView().controlSize(.small)` + cancel button instead of the
value-based bar.

- [ ] **Step 4: Strings (both tables)**

```
"onboarding.downloading_size" = EN "Downloading ~%.1f GB — the bar is shy, but bytes are flowing." / PT-BR "Baixando ~%.1f GB — a barra é tímida, mas os bytes estão fluindo.";
"onboarding.cancel_download" = EN "Cancel download" / PT-BR "Cancelar download";
```

(The old `onboarding.download_progress` key may be removed from BOTH tables
together with its last usage.)

- [ ] **Step 5: Verify** — `make test`, `make build`, launch smoke, key parity.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: honest indeterminate download progress with cancel"
```

---

## After all tasks

1. Final whole-branch review (most capable model) with the accumulated Minors.
2. PR `feat/correction-refine` → main; CI must pass (warm cache ≈ fast).
3. Author QA: correction PT/EN, refine loop, direct mode, ⌃T/⌃G, download cancel/retry, welcome guide, regression on translate.
4. Then: v1.0.0 release plan (sign/notarize/DMG) + repo público.

## Verification checklist (manual, author)

1. ⌃T translates; ⌃G corrects a PT text with typos ("Eu fui no mercado ontem e comprei umas coisa") keeping PT.
2. Refine: after a translation, type "more casual" → regenerates more casually; after a correction, "keep contractions" works.
3. Direct mode ON: ⌃G replaces the selection in TextEdit without any popup; with Wi-Fi off still works; an error (e.g. no model) opens the popup.
4. Menu shows both items with ⌃T/⌃G hints (no empty right column).
5. Welcome guide menu item reopens onboarding; final step shows both shortcuts.
6. Download: cancel mid-download → retry works; no lying percentage anywhere.
7. Regression: ⌘C/⌘⏎ popup shortcuts, clipboard survival, glossary, tones.
