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

    func testDemandsSymbolAndEmojiPreservation() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("Preserve emoji"))
        XCTAssertTrue(p.contains("keyboard shortcuts"))
    }

    func testDemandsTranslationOnlyOutput() {
        let p = builder.systemPrompt(source: .english, target: .portuguese,
                                     tone: .neutral, customInstructions: "", glossary: [])
        XCTAssertTrue(p.contains("ONLY the translated text"))
    }
}

extension PromptBuilderTests {
    private func request(mode: TranslationMode,
                         refinement: Refinement? = nil,
                         correctionTone: CorrectionTone = .keep) -> TranslationRequest {
        TranslationRequest(text: "Hey team, the deploy is done.",
                           source: .english, target: .portuguese,
                           tone: .formal, customInstructions: "Keep tech terms.",
                           glossary: ["deploy"], mode: mode, refinement: refinement,
                           correctionTone: correctionTone)
    }

    func testMessagesWithoutRefinementSendTheRawTextAsTheUserTurn() {
        let messages = builder.messages(for: request(mode: .translate))
        XCTAssertEqual(messages.map(\.role), [.system, .user])
        // The user turn is the untouched text — the system prompt owns all
        // instructions, so the model never confuses data with directives.
        XCTAssertEqual(messages[1].content, "Hey team, the deploy is done.")
    }

    func testRefinementCarriesOriginalPreviousAndFeedbackAsData() {
        let refinement = Refinement(previousOutput: "Olá time, o deploy está feito.",
                                    feedback: "de um tom mais formal")
        let messages = builder.messages(for: request(mode: .translate, refinement: refinement))
        XCTAssertEqual(messages.map(\.role), [.system, .user])
        let user = messages[1].content
        XCTAssertTrue(user.contains("Hey team, the deploy is done."))
        XCTAssertTrue(user.contains("Olá time, o deploy está feito."))
        XCTAssertTrue(user.contains("de um tom mais formal"))
        // The old shape sent the instruction template as a bare user message —
        // proofread mode would "correct" the template instead of obeying it.
        XCTAssertFalse(user.contains("not good enough"))
    }

    func testRefinementSystemPromptDefinesTheRewriteProtocol() {
        let refinement = Refinement(previousOutput: "prev", feedback: "shorter")
        let system = builder.messages(for: request(mode: .translate, refinement: refinement))[0].content
        XCTAssertTrue(system.contains("feedback"))
        XCTAssertTrue(system.contains("original text"))
        XCTAssertTrue(system.contains("English"))
        XCTAssertTrue(system.contains("Brazilian Portuguese"))
        XCTAssertTrue(system.contains("ONLY the new"))
    }

    func testCorrectionRefinementKeepsTheLanguageAndProtocol() {
        let refinement = Refinement(previousOutput: "prev", feedback: "more formal")
        let system = builder.messages(for: request(mode: .correct, refinement: refinement))[0].content
        XCTAssertTrue(system.contains("English"))
        XCTAssertTrue(system.contains("same language"))
        XCTAssertTrue(system.contains("feedback"))
        XCTAssertFalse(system.contains("Brazilian Portuguese"))
    }

    func testRefinementSystemPromptKeepsToneCustomAndGlossaryClauses() {
        let refinement = Refinement(previousOutput: "prev", feedback: "shorter")
        let system = builder.messages(for: request(mode: .translate, refinement: refinement))[0].content
        XCTAssertTrue(system.contains(Tone.formal.promptClause))
        XCTAssertTrue(system.contains("Keep tech terms."))
        XCTAssertTrue(system.contains("deploy"))
    }

    func testPlainModesKeepTheirDedicatedSystemPrompts() {
        let translate = builder.messages(for: request(mode: .translate))[0].content
        XCTAssertEqual(translate, builder.systemPrompt(source: .english, target: .portuguese,
                                                       tone: .formal,
                                                       customInstructions: "Keep tech terms.",
                                                       glossary: ["deploy"]))
        let correct = builder.messages(for: request(mode: .correct))[0].content
        XCTAssertEqual(correct, builder.correctionPrompt(language: .english, correctionTone: .keep,
                                                         customInstructions: "Keep tech terms.",
                                                         glossary: ["deploy"]))
    }

    func testCorrectionRefinementKeepAddsNoToneClause() {
        let refinement = Refinement(previousOutput: "prev", feedback: "more formal")
        let system = builder.messages(for: request(mode: .correct, refinement: refinement,
                                                    correctionTone: .keep))[0].content
        XCTAssertFalse(system.contains(Tone.formal.promptClause))
        XCTAssertFalse(system.contains(Tone.neutral.promptClause))
        XCTAssertFalse(system.contains(Tone.casual.promptClause))
    }

    func testCorrectionRefinementNonKeepUsesCorrectionToneNotTranslationTone() {
        let refinement = Refinement(previousOutput: "prev", feedback: "more formal")
        // The shared helper's translation `tone` is .formal; correctionTone here
        // is .casual — only the latter may surface in a .correct refinement.
        let system = builder.messages(for: request(mode: .correct, refinement: refinement,
                                                    correctionTone: .casual))[0].content
        XCTAssertTrue(system.contains(Tone.casual.promptClause))
        XCTAssertFalse(system.contains(Tone.formal.promptClause))
    }
}
