import Foundation
import Combine

public struct SettingsData: Codable, Equatable, Sendable {
    public var pair = LanguagePair(primary: .portuguese, secondary: .english)
    public var tone: Tone = .neutral
    public var customInstructions = ""
    public var correctionInstructions = ""
    public var glossary: [String] = []
    public var selectedModelID = ModelCatalog.recommended().id
    public var unloadAfterMinutes = 10
    public var didOnboard = false
    public var correctionReplacesDirectly = false
    public var correctionTone: CorrectionTone = .keep

    public init() {}

    /// Test seam: pins the fresh-install model recommendation to an explicit
    /// RAM size instead of this host's actual memory.
    public init(physicalMemoryGB: Double) {
        selectedModelID = ModelCatalog.recommended(forPhysicalMemoryGB: physicalMemoryGB).id
    }

    private enum CodingKeys: String, CodingKey {
        case pair, tone, customInstructions, correctionInstructions, glossary,
             selectedModelID, unloadAfterMinutes, didOnboard,
             correctionReplacesDirectly, correctionTone
    }

    /// Tolerant decoding: any missing key falls back to its default so adding
    /// fields never resets a user's persisted settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SettingsData()
        pair = try c.decodeIfPresent(LanguagePair.self, forKey: .pair) ?? defaults.pair
        tone = try c.decodeIfPresent(Tone.self, forKey: .tone) ?? defaults.tone
        customInstructions = try c.decodeIfPresent(String.self, forKey: .customInstructions) ?? defaults.customInstructions
        correctionInstructions = try c.decodeIfPresent(String.self, forKey: .correctionInstructions) ?? defaults.correctionInstructions
        glossary = try c.decodeIfPresent([String].self, forKey: .glossary) ?? defaults.glossary
        selectedModelID = try c.decodeIfPresent(String.self, forKey: .selectedModelID) ?? defaults.selectedModelID
        unloadAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .unloadAfterMinutes) ?? defaults.unloadAfterMinutes
        didOnboard = try c.decodeIfPresent(Bool.self, forKey: .didOnboard) ?? defaults.didOnboard
        correctionReplacesDirectly = try c.decodeIfPresent(Bool.self, forKey: .correctionReplacesDirectly) ?? defaults.correctionReplacesDirectly
        correctionTone = try c.decodeIfPresent(CorrectionTone.self, forKey: .correctionTone) ?? defaults.correctionTone
    }
}

public extension SettingsData {
    /// UserDefaults key for the persisted settings blob. Bump the suffix on
    /// breaking schema changes.
    static let storageKey = "settings.v1"

    /// Thread-safe snapshot of persisted settings, for non-main-actor readers.
    static func snapshot(from defaults: UserDefaults = .standard) -> SettingsData {
        guard let raw = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) else {
            return SettingsData()
        }
        return decoded
    }
}

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var data: SettingsData {
        didSet { schedulePersist() }
    }

    private let defaults: UserDefaults
    private var persistTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.data = SettingsData.snapshot(from: defaults)
    }

    /// Persistence is debounced so per-keystroke edits (e.g. the instructions
    /// field) don't JSON-encode and hit the disk on every character.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes pending changes immediately. Call on app termination.
    public func flush() {
        persistTask?.cancel()
        persistTask = nil
        guard let raw = try? JSONEncoder().encode(data) else { return }
        defaults.set(raw, forKey: SettingsData.storageKey)
    }
}
