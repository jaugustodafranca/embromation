public struct LanguagePair: Equatable, Codable, Sendable {
    public var primary: Language
    public var secondary: Language

    public init(primary: Language, secondary: Language) {
        self.primary = primary
        self.secondary = secondary
    }
}

public struct LanguagePairResolver: Sendable {
    public init() {}

    /// Detected == primary → secondary. Anything else (secondary, third language, nil) → primary.
    public func target(forDetected detected: Language?, pair: LanguagePair) -> Language {
        guard let detected else { return pair.primary }
        return detected == pair.primary ? pair.secondary : pair.primary
    }
}
