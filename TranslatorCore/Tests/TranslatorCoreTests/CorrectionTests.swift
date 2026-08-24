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
        let p = builder.correctionPrompt(language: .portuguese, correctionTone: .keep,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("proofreading"))
        XCTAssertTrue(p.contains("same language"))
        XCTAssertTrue(p.contains("Brazilian Portuguese"))
        XCTAssertTrue(p.contains("Preserve emoji"))
        XCTAssertTrue(p.contains("ONLY the corrected text"))
    }

    func testCorrectionPromptCarriesToneCustomAndGlossary() {
        let p = builder.correctionPrompt(language: .english, correctionTone: .casual,
                                         customInstructions: "Keep it short.",
                                         glossary: ["deploy"])
        XCTAssertTrue(p.contains(Tone.casual.promptClause))
        XCTAssertTrue(p.contains("Keep it short."))
        XCTAssertTrue(p.contains("deploy"))
    }

    func testCorrectionPromptKeepPreservesOriginalToneAndAddsNoClause() {
        // .keep must not promise "same tone" in the commitment sentence —
        // rewording an awkward sentence would read as breaking that promise.
        // Tone preservation lives in its own clause, phrased to coexist
        // with reordering (tone ≠ word order).
        let p = builder.correctionPrompt(language: .english, correctionTone: .keep,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("keeping the same language (English) and meaning."))
        XCTAssertFalse(p.contains("meaning and tone."))
        XCTAssertTrue(p.contains("Keep the writer's tone and level of formality."))
        XCTAssertFalse(p.contains(Tone.neutral.promptClause))
        XCTAssertFalse(p.contains(Tone.formal.promptClause))
        XCTAssertFalse(p.contains(Tone.casual.promptClause))
    }

    func testCorrectionPromptNonKeepOmitsTonePreservationClause() {
        let p = builder.correctionPrompt(language: .english, correctionTone: .formal,
                                         customInstructions: "", glossary: [])
        XCTAssertFalse(p.contains("Keep the writer's tone and level of formality."))
    }

    func testCorrectionPromptAsksForNaturalRewordingWithMeaningGuard() {
        // Awkward-but-grammatical sentences fall outside the error checklist,
        // so naturalness must be its own category — with the meaning guard in
        // the same sentence so the license to rewrite never becomes a license
        // to paraphrase the intent away.
        let p = builder.correctionPrompt(language: .english, correctionTone: .keep,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("rewrite or reorder it"))
        XCTAssertTrue(p.contains("fluent native speaker"))
        XCTAssertTrue(p.contains("NEVER change the meaning"))
        XCTAssertTrue(p.contains("do not add information, remove information"))
    }

    func testCorrectionRefinementPromptAsksForNaturalRewording() {
        var request = TranslationRequest(text: "texto", source: .english, target: .english,
                                         tone: .neutral, customInstructions: "", glossary: [])
        request.mode = .correct
        request.refinement = Refinement(previousOutput: "Texto.", feedback: "mais natural")
        let system = builder.messages(for: request).first { $0.role == .system }
        XCTAssertNotNil(system)
        XCTAssertTrue(system?.content.contains("rewrite or reorder it") ?? false)
        XCTAssertTrue(system?.content.contains("NEVER change the meaning") ?? false)
    }

    func testCorrectionPromptNonKeepDropsToneWordFromLineAndAppendsMatchingClause() {
        let p = builder.correctionPrompt(language: .english, correctionTone: .formal,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("keeping the same language (English) and meaning."))
        XCTAssertFalse(p.contains("meaning and tone."))
        XCTAssertTrue(p.contains(Tone.formal.promptClause))
    }

    func testCorrectionPromptListsConcreteErrorCategories() {
        // Small on-device models are more likely to actually apply a fix
        // when told exactly what to look for instead of a generic
        // "fix grammar" instruction — regression test for that checklist.
        let p = builder.correctionPrompt(language: .english, correctionTone: .keep,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("capitalization"))
        XCTAssertTrue(p.contains("subject-verb agreement"))
        XCTAssertTrue(p.contains("punctuation"))
        XCTAssertTrue(p.contains("even in short, casual, or technical messages"))
    }

    func testAllPromptsMirrorTheInputsFormattingStyle() {
        // Markdown, Slack and WhatsApp each mark up text differently
        // (**bold** vs *bold*), and the model likes to decorate output with
        // emphasis the input never had. Instead of naming dialects, every
        // prompt pins the output to the input's own formatting symbols:
        // reuse what's there, never convert, never introduce new ones.
        let clause = "never introduce formatting symbols the message does not already contain"
        let correction = builder.correctionPrompt(language: .english, correctionTone: .keep,
                                                  customInstructions: "", glossary: [])
        XCTAssertTrue(correction.contains(clause))
        let translation = builder.systemPrompt(source: .english, target: .portuguese,
                                               tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertTrue(translation.contains(clause))
        var refinement = TranslationRequest(text: "texto", source: .english, target: .english,
                                            tone: .neutral, customInstructions: "", glossary: [])
        refinement.mode = .correct
        refinement.refinement = Refinement(previousOutput: "Texto.", feedback: "melhor")
        let system = builder.messages(for: refinement).first { $0.role == .system }
        XCTAssertTrue(system?.content.contains(clause) ?? false)
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
