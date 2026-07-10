import Foundation
import Combine

public struct SettingsData: Codable, Equatable, Sendable {
    public var pair = LanguagePair(primary: .portuguese, secondary: .english)
    public var tone: Tone = .neutral
    public var customInstructions = ""
    public var glossary: [String] = []
    public var selectedModelID = ModelCatalog.default.id
    public var unloadAfterMinutes = 10
    public var didOnboard = false

    public init() {}
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
        didSet { persist() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.data = SettingsData.snapshot(from: defaults)
    }

    private func persist() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        defaults.set(raw, forKey: SettingsData.storageKey)
    }
}
