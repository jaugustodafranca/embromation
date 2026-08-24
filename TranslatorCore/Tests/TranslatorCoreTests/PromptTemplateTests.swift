import XCTest
@testable import TranslatorCore

/// The base instruction block of the translation/correction prompts is
/// user-editable in Settings. An empty template means "use the built-in
/// default"; placeholders keep the language names dynamic either way.
final class PromptTemplateTests: XCTestCase {
    let builder = PromptBuilder()

    func testDefaultTemplatesExposePlaceholders() {
        XCTAssertTrue(PromptBuilder.defaultTranslationTemplate.contains("{source}"))
        XCTAssertTrue(PromptBuilder.defaultTranslationTemplate.contains("{target}"))
        XCTAssertTrue(PromptBuilder.defaultCorrectionTemplate.contains("{language}"))
    }

    func testEmptyTemplateProducesTheBuiltInPrompt() {
        let explicit = builder.systemPrompt(source: .english, target: .portuguese,
                                            tone: .neutral, customInstructions: "", glossary: [],
                                            template: "")
        let implicit = builder.systemPrompt(source: .english, target: .portuguese,
                                            tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertEqual(explicit, implicit)
        XCTAssertTrue(implicit.contains("You are a translation engine."))
    }

    func testCustomTranslationTemplateSubstitutesLanguages() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "", glossary: [],
                                     template: "Translate from {source} to {target}, pirate style.")
        XCTAssertTrue(p.contains("Translate from English to Brazilian Portuguese, pirate style."))
        XCTAssertFalse(p.contains("You are a translation engine."))
    }

    func testCustomTemplateStillGetsToneGlossaryAndOutputContract() {
        // The editable part is the base block only — tone, custom
        // instructions, glossary and the reply-only contract stay appended
        // so editing the prompt can't silently break the rest of Settings.
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .formal, customInstructions: "Keep it short.",
                                     glossary: ["deploy"],
                                     template: "Translate from {source} to {target}.")
        XCTAssertTrue(p.contains(Tone.formal.promptClause))
        XCTAssertTrue(p.contains("Keep it short."))
        XCTAssertTrue(p.contains("deploy"))
        XCTAssertTrue(p.contains("ONLY the translated text"))
    }

    func testCustomCorrectionTemplateSubstitutesLanguage() {
        let p = builder.correctionPrompt(language: .portuguese, correctionTone: .keep,
                                         customInstructions: "", glossary: [],
                                         template: "Fix my {language} text.")
        XCTAssertTrue(p.contains("Fix my Brazilian Portuguese text."))
        XCTAssertTrue(p.contains("ONLY the corrected text"))
    }

    func testRequestCarriesTemplatesIntoMessages() {
        var request = TranslationRequest(text: "hola", source: .english, target: .portuguese,
                                         tone: .neutral, customInstructions: "", glossary: [])
        request.translationTemplate = "Translate from {source} to {target}, briefly."
        let system = builder.messages(for: request).first { $0.role == .system }
        XCTAssertTrue(system?.content.contains("Translate from English to Brazilian Portuguese, briefly.") ?? false)

        var correction = TranslationRequest(text: "hola", source: .portuguese, target: .portuguese,
                                            tone: .neutral, customInstructions: "", glossary: [],
                                            mode: .correct)
        correction.correctionTemplate = "Fix my {language} text."
        let correctionSystem = builder.messages(for: correction).first { $0.role == .system }
        XCTAssertTrue(correctionSystem?.content.contains("Fix my Brazilian Portuguese text.") ?? false)
    }
}
