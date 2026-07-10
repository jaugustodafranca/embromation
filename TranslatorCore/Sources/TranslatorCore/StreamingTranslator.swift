public struct TranslationRequest: Equatable, Sendable {
    public var text: String
    public var source: Language
    public var target: Language
    public var tone: Tone
    public var customInstructions: String
    public var glossary: [String]

    public init(text: String, source: Language, target: Language,
                tone: Tone, customInstructions: String, glossary: [String]) {
        self.text = text
        self.source = source
        self.target = target
        self.tone = tone
        self.customInstructions = customInstructions
        self.glossary = glossary
    }
}

public protocol StreamingTranslator: Sendable {
    /// Yields incremental text chunks; concatenated chunks form the full translation.
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}
