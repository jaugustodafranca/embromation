public struct Language: Equatable, Hashable, Codable, Sendable {
    /// ISO 639-1 code, matches NLLanguage.rawValue (e.g. "pt", "en").
    public let code: String
    /// English name used inside prompts ("Brazilian Portuguese").
    public let englishName: String

    public init(code: String, englishName: String) {
        self.code = code
        self.englishName = englishName
    }

    public static let portuguese = Language(code: "pt", englishName: "Brazilian Portuguese")
    public static let english = Language(code: "en", englishName: "English")
    public static let spanish = Language(code: "es", englishName: "Spanish")
    public static let french = Language(code: "fr", englishName: "French")
    public static let all: [Language] = [.portuguese, .english, .spanish, .french]
}
