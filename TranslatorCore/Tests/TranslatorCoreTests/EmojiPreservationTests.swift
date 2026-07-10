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
