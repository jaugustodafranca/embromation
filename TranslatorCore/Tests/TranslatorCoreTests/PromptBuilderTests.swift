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
