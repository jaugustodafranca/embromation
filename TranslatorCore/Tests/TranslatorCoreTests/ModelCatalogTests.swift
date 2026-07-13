import XCTest
@testable import TranslatorCore

final class ModelCatalogTests: XCTestCase {
    func testRecommendsFlagshipModelAt16GBAndAbove() {
        XCTAssertEqual(ModelCatalog.recommended(forPhysicalMemoryGB: 16), ModelCatalog.qwen3_4b)
        XCTAssertEqual(ModelCatalog.recommended(forPhysicalMemoryGB: 64), ModelCatalog.qwen3_4b)
    }

    func testRecommendsMidTierModelBetween8And16GB() {
        XCTAssertEqual(ModelCatalog.recommended(forPhysicalMemoryGB: 8), ModelCatalog.llama32_3b)
        XCTAssertEqual(ModelCatalog.recommended(forPhysicalMemoryGB: 15), ModelCatalog.llama32_3b)
    }

    func testRecommendsLightModelBelow8GB() {
        XCTAssertEqual(ModelCatalog.recommended(forPhysicalMemoryGB: 7.9), ModelCatalog.qwen25_1_5b)
        XCTAssertEqual(ModelCatalog.recommended(forPhysicalMemoryGB: 4), ModelCatalog.qwen25_1_5b)
    }

    /// Smoke test for the injectable default parameter: whatever this
    /// machine reports, the result must be a real catalog entry.
    func testDefaultParameterResolvesToARealCatalogEntry() {
        XCTAssertTrue(ModelCatalog.all.contains(ModelCatalog.recommended()))
    }
}
