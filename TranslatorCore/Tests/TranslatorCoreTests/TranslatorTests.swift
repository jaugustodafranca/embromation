import XCTest
@testable import TranslatorCore

final class TranslatorTests: XCTestCase {
    func testFakeTranslatorStreamsCannedTextInOrder() async throws {
        let fake = FakeTranslator(canned: "O livro está sobre a mesa.")
        let request = TranslationRequest(text: "The book is on the table.",
                                         source: .english, target: .portuguese,
                                         tone: .neutral, customInstructions: "", glossary: [])
        var chunks: [String] = []
        for try await chunk in fake.translate(request) {
            chunks.append(chunk)
        }
        XCTAssertGreaterThan(chunks.count, 1, "must stream in multiple chunks")
        XCTAssertEqual(chunks.joined(), "O livro está sobre a mesa.")
    }

    func testCatalogDefaultIsListedAndUnknownIDFallsBack() {
        XCTAssertTrue(ModelCatalog.all.contains(ModelCatalog.default))
        XCTAssertEqual(ModelCatalog.spec(for: "does/not-exist"), ModelCatalog.default)
        XCTAssertEqual(ModelCatalog.spec(for: ModelCatalog.all[1].id), ModelCatalog.all[1])
    }
}
