import NaturalLanguage

public struct LanguageDetector: Sendable {
    public init() {}

    public func detect(_ text: String) -> Language? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        if let known = Language.all.first(where: { $0.code == dominant.rawValue }) {
            return known
        }
        let name = Locale(identifier: "en").localizedString(forLanguageCode: dominant.rawValue) ?? dominant.rawValue
        return Language(code: dominant.rawValue, englishName: name)
    }
}
