public enum TranslationMode: Equatable, Sendable {
    /// Translate from `source` to `target`.
    case translate
    /// Fix grammar/spelling/punctuation keeping the same language and meaning.
    case correct
}

public struct Refinement: Equatable, Sendable {
    public var previousOutput: String
    public var feedback: String

    public init(previousOutput: String, feedback: String) {
        self.previousOutput = previousOutput
        self.feedback = feedback
    }
}

public struct TranslationRequest: Equatable, Sendable {
    public var text: String
    public var source: Language
    public var target: Language
    public var tone: Tone
    public var customInstructions: String
    public var glossary: [String]
    public var mode: TranslationMode
    public var refinement: Refinement?
    /// Tone for `.correct` requests only; `.translate` requests use `tone`.
    public var correctionTone: CorrectionTone

    public init(text: String, source: Language, target: Language,
                tone: Tone, customInstructions: String, glossary: [String],
                mode: TranslationMode = .translate, refinement: Refinement? = nil,
                correctionTone: CorrectionTone = .keep) {
        self.text = text
        self.source = source
        self.target = target
        self.tone = tone
        self.customInstructions = customInstructions
        self.glossary = glossary
        self.mode = mode
        self.refinement = refinement
        self.correctionTone = correctionTone
    }
}

public protocol StreamingTranslator: Sendable {
    /// Yields incremental text chunks; concatenated chunks form the full translation.
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error>
}
