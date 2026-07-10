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

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var data: SettingsData {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let key = "settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            self.data = decoded
        } else {
            self.data = SettingsData()
        }
    }

    private func persist() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        defaults.set(raw, forKey: Self.key)
    }
}
