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
        let p = builder.correctionPrompt(language: .english, correctionTone: .keep,
                                         customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("keeping the same language (English), meaning and tone."))
        XCTAssertFalse(p.contains(Tone.neutral.promptClause))
        XCTAssertFalse(p.contains(Tone.formal.promptClause))
        XCTAssertFalse(p.contains(Tone.casual.promptClause))
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
