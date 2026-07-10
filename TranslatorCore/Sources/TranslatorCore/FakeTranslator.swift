public struct FakeTranslator: StreamingTranslator {
    public let canned: String
    public let wordDelay: Duration

    public init(canned: String = "O livro está sobre a mesa.", wordDelay: Duration = .zero) {
        self.canned = canned
        self.wordDelay = wordDelay
    }

    public func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        let text = request.refinement.map { "\(canned) [\($0.feedback)]" } ?? canned
        let words = text.split(separator: " ").map(String.init)
        let delay = wordDelay
        return AsyncThrowingStream { continuation in
            Task {
                for (index, word) in words.enumerated() {
                    if delay != .zero { try? await Task.sleep(for: delay) }
                    continuation.yield(index == 0 ? word : " " + word)
                }
                continuation.finish()
            }
        }
    }
}
