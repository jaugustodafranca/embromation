import XCTest
@testable import TranslatorCore

final class LanguageDetectionTests: XCTestCase {
    let detector = LanguageDetector()
    let resolver = LanguagePairResolver()
    let pair = LanguagePair(primary: .portuguese, secondary: .english)

    func testDetectsPortugueseAndEnglish() {
        XCTAssertEqual(detector.detect("Olá, tudo bem com você hoje?")?.code, "pt")
        XCTAssertEqual(detector.detect("The book is on the table.")?.code, "en")
    }

    func testEmptyTextDetectsNil() {
        XCTAssertNil(detector.detect(""))
        XCTAssertNil(detector.detect("   \n"))
    }

    func testResolverFlipsThePair() {
        XCTAssertEqual(resolver.target(forDetected: .portuguese, pair: pair), .english)
        XCTAssertEqual(resolver.target(forDetected: .english, pair: pair), .portuguese)
    }

    func testThirdLanguageAndNilResolveToPrimary() {
        XCTAssertEqual(resolver.target(forDetected: .french, pair: pair), .portuguese)
        XCTAssertEqual(resolver.target(forDetected: nil, pair: pair), .portuguese)
    }
}
