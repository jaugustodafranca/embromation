/// Suppresses a leading `<think>…</think>` block from a streamed response.
/// Reasoning models (e.g. Qwen3) emit one before the actual answer — even
/// with thinking disabled they still produce an empty pair — and reasoning
/// tokens must never reach the user.
public struct ThinkBlockFilter: Sendable {
    private enum State { case buffering, passing }
    private var state: State = .buffering
    private var buffer = ""

    public init() {}

    /// Feed one streamed chunk; returns the text to surface now, if any.
    public mutating func filter(_ chunk: String) -> String? {
        if state == .passing { return chunk }

        buffer += chunk
        let content = buffer.drop(while: \.isWhitespace)
        guard !content.isEmpty else { return nil }

        if content.hasPrefix("<think>") {
            guard let close = content.range(of: "</think>") else { return nil }
            state = .passing
            let answer = content[close.upperBound...].drop(while: \.isWhitespace)
            buffer = ""
            return answer.isEmpty ? nil : String(answer)
        }

        // Could this still become "<think>" once more chunks arrive?
        if "<think>".hasPrefix(content) { return nil }

        state = .passing
        let output = String(content)
        buffer = ""
        return output
    }

    /// Call when the stream ends: releases anything still buffered
    /// (e.g. an unterminated block or a very short response).
    public mutating func finish() -> String? {
        defer { buffer = ""; state = .passing }
        let content = buffer.drop(while: \.isWhitespace)
        guard !content.isEmpty, !content.hasPrefix("<think>") else { return nil }
        return String(content)
    }
}
