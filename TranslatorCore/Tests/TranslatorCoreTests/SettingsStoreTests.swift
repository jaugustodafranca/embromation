import XCTest
@testable import TranslatorCore

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testDefaultsMatchSpec() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.data.pair, LanguagePair(primary: .portuguese, secondary: .english))
        XCTAssertEqual(store.data.glossary, [])
        // RAM-aware default: whatever this host reports, a fresh store must
        // match the pure recommendation function, not a fixed model.
        XCTAssertEqual(store.data.selectedModelID, ModelCatalog.recommended().id)
        XCTAssertEqual(store.data.unloadAfterMinutes, 10)
        XCTAssertFalse(store.data.didOnboard)
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
        store.data.glossary = ["deploy", "commit"]
        store.data.didOnboard = true
        store.flush()

        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.glossary, ["deploy", "commit"])
        XCTAssertTrue(reloaded.data.didOnboard)
    }

    @MainActor
    func testEngineDefaultsToMLXAndSurvivesReload() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        // Existing installs must keep their behavior: the local MLX engine
        // stays the default until the user opts into Apple Intelligence.
        XCTAssertEqual(store.data.engine, .mlx)
        store.data.engine = .appleIntelligence
        store.flush()
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.engine, .appleIntelligence)
    }

    func testDecodingBlobWithoutEngineKeyFallsBackToMLX() throws {
        let old = """
        {"tone":"formal","didOnboard":true}
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.engine, .mlx)
        XCTAssertTrue(decoded.didOnboard)
    }

    @MainActor
    func testPromptTemplatesDefaultEmptyAndSurviveReload() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.data.translationPromptTemplate, "")
        XCTAssertEqual(store.data.correctionPromptTemplate, "")
        store.data.translationPromptTemplate = "Translate from {source} to {target}."
        store.data.correctionPromptTemplate = "Fix my {language} text."
        store.flush()
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.translationPromptTemplate, "Translate from {source} to {target}.")
        XCTAssertEqual(reloaded.data.correctionPromptTemplate, "Fix my {language} text.")
    }

    @MainActor
    func testRestoreDefaultsResetsEverythingButOnboarding() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        store.data.glossary = ["deploy"]
        store.data.translationPromptTemplate = "custom"
        store.data.engine = .appleIntelligence
        store.data.didOnboard = true
        store.restoreDefaults()
        XCTAssertEqual(store.data.glossary, [])
        XCTAssertEqual(store.data.translationPromptTemplate, "")
        XCTAssertEqual(store.data.engine, .mlx)
        // Resetting settings must never re-run onboarding.
        XCTAssertTrue(store.data.didOnboard)
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
        XCTAssertEqual(decoded.glossary, ["deploy"])
        XCTAssertEqual(decoded.unloadAfterMinutes, 5)
        XCTAssertTrue(decoded.didOnboard)
        XCTAssertFalse(decoded.correctionReplacesDirectly)
    }

    func testDecodingBlobWithRetiredKeysStillDecodes() throws {
        // Blobs persisted before tone/instructions were retired still carry
        // those keys — they must be ignored, not break decoding.
        let old = """
        {"pair":{"primary":{"code":"pt","englishName":"Brazilian Portuguese"},"secondary":{"code":"en","englishName":"English"}},"tone":"formal","customInstructions":"tech","correctionInstructions":"","correctionTone":"casual","glossary":["deploy"],"selectedModelID":"mlx-community/Qwen3-4B-4bit","unloadAfterMinutes":5,"didOnboard":true,"correctionReplacesDirectly":true}
        """
        let decoded = try JSONDecoder().decode(SettingsData.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.correctionReplacesDirectly)
        XCTAssertEqual(decoded.glossary, ["deploy"])
    }

    @MainActor
    func testDebouncedPersistLandsWithoutExplicitFlush() async {
        let suite = "test-\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        store.data.glossary = ["deploy"]
        try? await Task.sleep(for: .milliseconds(600))
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.data.glossary, ["deploy"])
    }
}
