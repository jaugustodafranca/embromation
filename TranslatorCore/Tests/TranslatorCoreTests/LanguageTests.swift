import XCTest
@testable import TranslatorCore

final class LanguageTests: XCTestCase {
    func testBuiltinLanguagesHaveCodesAndNames() {
        XCTAssertEqual(Language.portuguese.code, "pt")
        XCTAssertEqual(Language.english.code, "en")
        XCTAssertEqual(Language.portuguese.englishName, "Brazilian Portuguese")
        XCTAssertTrue(Language.all.contains(.english))
    }

    func testToneClausesAreNonEmptyAndDistinct() {
        let clauses = Tone.allCases.map(\.promptClause)
        XCTAssertEqual(Set(clauses).count, Tone.allCases.count)
        XCTAssertFalse(clauses.contains(where: \.isEmpty))
    }
}
