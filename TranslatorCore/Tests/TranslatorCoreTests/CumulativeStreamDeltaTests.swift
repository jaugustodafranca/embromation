import XCTest
@testable import TranslatorCore

/// Apple's FoundationModels streams cumulative snapshots ("Ol", "Olá mu",
/// "Olá mundo"), while `StreamingTranslator` promises incremental chunks whose
/// concatenation is the full text. This tracker converts one into the other.
final class CumulativeStreamDeltaTests: XCTestCase {
    func testEmitsOnlyTheNewSuffixOfEachSnapshot() {
        var delta = CumulativeStreamDelta()
        XCTAssertEqual(delta.consume("Ol"), "Ol")
        XCTAssertEqual(delta.consume("Olá mu"), "á mu")
        XCTAssertEqual(delta.consume("Olá mundo"), "ndo")
    }

    func testRepeatedSnapshotEmitsNothing() {
        var delta = CumulativeStreamDelta()
        XCTAssertEqual(delta.consume("Olá"), "Olá")
        XCTAssertNil(delta.consume("Olá"))
    }

    func testEmptyFirstSnapshotEmitsNothing() {
        var delta = CumulativeStreamDelta()
        XCTAssertNil(delta.consume(""))
        XCTAssertEqual(delta.consume("Oi"), "Oi")
    }

    func testNonExtendingSnapshotResetsBaselineWithoutDuplicating() {
        // Defensive: snapshots should be monotonic, but if one ever rewrites
        // earlier text, re-emitting from scratch would duplicate what the
        // user already saw. Adopt the new baseline and emit nothing.
        var delta = CumulativeStreamDelta()
        XCTAssertEqual(delta.consume("Olá mundo"), "Olá mundo")
        XCTAssertNil(delta.consume("Oi mundo"))
        XCTAssertEqual(delta.consume("Oi mundo!"), "!")
    }
}
