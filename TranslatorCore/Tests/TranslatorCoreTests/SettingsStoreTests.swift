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
        // RAM-aware default: whatever this host reports, a fresh store must
        // match the pure recommendation function, not a fixed model.
        XCTAssertEqual(store.data.selectedModelID, ModelCatalog.recommended().id)
        XCTAssertEqual(store.data.unloadAfterMinutes, 10)
        XCTAssertFalse(store.data.didOnboard)
        XCTAssertEqual(store.data.correctionTone, .keep)
    }

    /// Proves the fresh-install default is wired to the RAM-aware
    /// recommendation, independent of the actual host machine's memory.
    func testFreshSettingsDataOn8GBMachineDefaultsToModelItCanRun() {
        let fresh = SettingsData(physicalMemoryGB: 8)
        let spec = ModelCatalog.spec(for: fresh.selectedModelID)
        XCTAssertLessThanOrEqual(spec.minRAMGB, 8)
    }

    @MainActor
    func testMutationsSurviveReload() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        store.data.tone = .formal
        store.data.glossary = ["deploy", "commit"]
        store.data.didOnboard = true
        store.flush()

        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.tone, .formal)
        XCTAssertEqual(reloaded.data.glossary, ["deploy", "commit"])
        XCTAssertTrue(reloaded.data.didOnboard)
    }

    @MainActor
    func testCorrectionFlowDefaultsToPopup() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.data.correctionReplacesDirectly)
    }

    func testDecodingOldBlobWithoutNewKeysKeepsExistingValues() throws {
        // Blob shape persisted by the MVP (no correctionReplacesDirectly key).
        let old = """
        {"pair":{"primary":{"code":"pt","englishName":"Brazilian Portuguese"},"secondary":{"code":"en","englishName":"English"}},"tone":"formal","customInstructions":"tech","glossary":["deploy"],"selectedModelID":"mlx-community/Qwen3-4B-4bit","unloadAfterMinutes":5,"didOnboard":true}
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.tone, .formal)
        XCTAssertEqual(decoded.glossary, ["deploy"])
        XCTAssertEqual(decoded.unloadAfterMinutes, 5)
        XCTAssertTrue(decoded.didOnboard)
        XCTAssertFalse(decoded.correctionReplacesDirectly)
        XCTAssertEqual(decoded.correctionInstructions, "")
    }

    func testDecodingBlobWithoutCorrectionToneDefaultsToKeep() throws {
        // Blob shape persisted before this feature (no correctionTone key), but
        // otherwise up to date — includes correctionReplacesDirectly.
        let old = """
        {"pair":{"primary":{"code":"pt","englishName":"Brazilian Portuguese"},"secondary":{"code":"en","englishName":"English"}},"tone":"formal","customInstructions":"tech","correctionInstructions":"","glossary":["deploy"],"selectedModelID":"mlx-community/Qwen3-4B-4bit","unloadAfterMinutes":5,"didOnboard":true,"correctionReplacesDirectly":true}
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.correctionTone, .keep)
        // Sibling fields from the previous migration still decode correctly.
        XCTAssertEqual(decoded.tone, .formal)
        XCTAssertTrue(decoded.correctionReplacesDirectly)
    }

    @MainActor
    func testDebouncedPersistLandsWithoutExplicitFlush() async {
        let suite = "test-\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        store.data.tone = .casual
        try? await Task.sleep(for: .milliseconds(600))
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.tone, .casual)
    }
}
