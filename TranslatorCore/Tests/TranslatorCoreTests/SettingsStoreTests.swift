import XCTest
@testable import TranslatorCore

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testDefaultsMatchSpec() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.data.pair, LanguagePair(primary: .portuguese, secondary: .english))
        XCTAssertEqual(store.data.tone, .neutral)
        XCTAssertEqual(store.data.glossary, [])
        XCTAssertEqual(store.data.selectedModelID, ModelCatalog.default.id)
        XCTAssertEqual(store.data.unloadAfterMinutes, 10)
        XCTAssertFalse(store.data.didOnboard)
    }

    @MainActor
    func testMutationsSurviveReload() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.data.tone = .formal
        store.data.glossary = ["deploy", "commit"]
        store.data.didOnboard = true

        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.tone, .formal)
        XCTAssertEqual(reloaded.data.glossary, ["deploy", "commit"])
        XCTAssertTrue(reloaded.data.didOnboard)
    }
}
