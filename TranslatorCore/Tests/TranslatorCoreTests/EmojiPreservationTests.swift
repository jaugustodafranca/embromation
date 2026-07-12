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

    func testRepairKeepsEmptyOutputEmpty() {
        // Appending the input's trailing emoji to an empty completion would
        // fabricate output ("" -> " 🎉") and bypass the caller's
        // empty-response guard — direct-replace would paste it over the
        // user's real selection.
        XCTAssertEqual(EmojiPreservation.repair(input: "Lançou! 🎉", output: ""), "")
    }

    func testRepairKeepsWhitespaceOnlyOutputEffectivelyEmpty() {
        let repaired = EmojiPreservation.repair(input: "Lançou! 🎉", output: " \n")
        XCTAssertTrue(repaired.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testRepairCollapsesHalfFlagOnlyOutputToEmpty() {
        XCTAssertEqual(EmojiPreservation.repair(input: "Feito. 🇧🇷", output: "🇧"), "")
    }
}

extension EmojiPreservationTests {
    func testDroppedKeycapEmojiIsDetected() {
        // Keycaps (digit + U+FE0F + U+20E3) have no Emoji_Presentation scalar,
        // so they slip past a presentation-only check.
        let missing = EmojiPreservation.missingEmoji(
            input: "Top 3: 1️⃣ 2️⃣ 3️⃣", output: "Top 3:")
        XCTAssertEqual(missing, ["1️⃣", "2️⃣", "3️⃣"])
    }

    func testRepairAppendsDroppedTrailingKeycap() {
        let repaired = EmojiPreservation.repair(input: "Passo 1️⃣", output: "Step")
        XCTAssertEqual(repaired, "Step 1️⃣")
    }
}
