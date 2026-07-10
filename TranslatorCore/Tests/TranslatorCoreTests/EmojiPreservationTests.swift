import XCTest
@testable import TranslatorCore

final class EmojiPreservationTests: XCTestCase {
    func testTruncatedFlagIsDetected() {
        // The real bug: 🇧🇷 came back as a lone 🇧 (half a flag).
        let missing = EmojiPreservation.missingEmoji(
            input: "Chega de embromation. 🇧🇷",
            output: "Chega de embromation. 🇧")
        XCTAssertEqual(missing, ["🇧🇷"])
    }

    func testDroppedEmojiIsDetected() {
        let missing = EmojiPreservation.missingEmoji(
            input: "Boa sorte 🤞 com o deploy 🚀",
            output: "Boa sorte com o deploy")
        XCTAssertEqual(missing, ["🤞", "🚀"])
    }

    func testPreservedEmojiPasses() {
        let missing = EmojiPreservation.missingEmoji(
            input: "Funcionou! 🎉🇧🇷",
            output: "It worked! 🎉🇧🇷")
        XCTAssertTrue(missing.isEmpty)
    }

    func testPlainTextAndPunctuationAreIgnored() {
        let missing = EmojiPreservation.missingEmoji(
            input: "Aperte ⌃T para traduzir, ok? (100%)",
            output: "Press the shortcut to translate.")
        XCTAssertTrue(missing.isEmpty)
    }
}

extension EmojiPreservationTests {
    func testRepairFixesTruncatedTrailingFlag() {
        // The observed bug: "🇧🇷" came back as a lone boxed 🇧.
        let repaired = EmojiPreservation.repair(
            input: "Usa à vontade e me traz o que incomodar. 🇧🇷",
            output: "Use as you like and bring me what annoys you. 🇧")
        XCTAssertEqual(repaired, "Use as you like and bring me what annoys you. 🇧🇷")
    }

    func testRepairAppendsDroppedTrailingEmoji() {
        let repaired = EmojiPreservation.repair(
            input: "Boa sorte! 🤞",
            output: "Good luck!")
        XCTAssertEqual(repaired, "Good luck! 🤞")
    }

    func testRepairKeepsAlreadyCorrectOutput() {
        let repaired = EmojiPreservation.repair(
            input: "Funcionou! 🎉🇧🇷",
            output: "It worked! 🎉🇧🇷")
        XCTAssertEqual(repaired, "It worked! 🎉🇧🇷")
    }

    func testRepairLeavesMiddleEmojiToTheCheck() {
        // A dropped emoji in the middle can't be repositioned safely.
        let repaired = EmojiPreservation.repair(
            input: "Boa sorte 🤞 com o deploy.",
            output: "Good luck with the deploy.")
        XCTAssertEqual(repaired, "Good luck with the deploy.")
        XCTAssertEqual(EmojiPreservation.missingEmoji(
            input: "Boa sorte 🤞 com o deploy.", output: repaired), ["🤞"])
    }
}
