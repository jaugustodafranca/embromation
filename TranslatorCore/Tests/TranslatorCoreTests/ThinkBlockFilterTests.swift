import XCTest
@testable import TranslatorCore

final class ThinkBlockFilterTests: XCTestCase {
    private func run(_ chunks: [String]) -> String {
        var filter = ThinkBlockFilter()
        var output = chunks.compactMap { filter.filter($0) }.joined()
        if let tail = filter.finish() { output += tail }
        return output
    }

    func testPlainTextPassesThrough() {
        XCTAssertEqual(run(["O livro", " está", " sobre a mesa."]),
                       "O livro está sobre a mesa.")
    }

    func testEmptyThinkBlockIsDropped() {
        XCTAssertEqual(run(["<think>\n\n</think>\n\nO livro está sobre a mesa."]),
                       "O livro está sobre a mesa.")
    }

    func testThinkBlockWithReasoningIsDroppedAcrossChunks() {
        XCTAssertEqual(run(["<th", "ink>the user wants", " a translation</th", "ink>\n", "O livro."]),
                       "O livro.")
    }

    func testUnterminatedThinkBlockYieldsNothing() {
        XCTAssertEqual(run(["<think>reasoning that never ends"]), "")
    }

    func testShortAnswerNotMistakenForThinkPrefix() {
        XCTAssertEqual(run(["<", "3 amor"]), "<3 amor")
    }

    func testLeadingWhitespaceAfterThinkBlockIsDroppedAcrossChunks() {
        // Regression: when </think> closes in one chunk and the blank line +
        // answer arrive in the NEXT chunk (routine with real reasoning
        // content, since the model emits them as separate generation
        // steps), the filter must keep trimming — not just on the chunk
        // where </think> itself was found.
        XCTAssertEqual(run(["<think>reasoning</think>", "\n\nThe problem is..."]),
                       "The problem is...")
    }

    func testLeadingWhitespaceSplitAcrossManyChunksIsDropped() {
        XCTAssertEqual(run(["<think>x</think>", "\n", "\n", " ", "Hello"]),
                       "Hello")
    }
}
