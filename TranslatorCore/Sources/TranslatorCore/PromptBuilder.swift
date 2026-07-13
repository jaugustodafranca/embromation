import Foundation

/// One turn of the chat sent to the model. The engine maps these onto its own
/// chat type; keeping the assembly here makes the full prompt testable.
public struct ChatMessage: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case system, user }
    public var role: Role
    public var content: String

    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }
    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }
}

public struct PromptBuilder: Sendable {
    public init() {}

    public func systemPrompt(
        source: Language,
        target: Language,
        tone: Tone,
        customInstructions: String,
        glossary: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("You are a translation engine. Translate the user's message from \(source.englishName) to \(target.englishName).")
        lines.append("Preserve emoji, keyboard shortcuts (like ⌃T), code, URLs, numbers and any other symbols exactly as written — never drop or translate them.")
        lines.append(tone.promptClause)
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append(custom)
        }
        if !glossary.isEmpty {
            lines.append("Keep these terms exactly as written, never translate them: \(glossary.joined(separator: ", ")).")
        }
        lines.append("Reply with ONLY the translated text. No explanations, no quotes, no notes.")
        return lines.joined(separator: "\n")
    }

    public func correctionPrompt(
        language: Language,
        tone: Tone,
        customInstructions: String,
        glossary: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("You are a proofreading engine. Fix grammar, spelling and punctuation of the user's message, keeping the same language (\(language.englishName)), meaning and tone.")
        lines.append("Preserve emoji, keyboard shortcuts (like ⌃T), code, URLs, numbers and any other symbols exactly as written — never drop or translate them.")
        lines.append(tone.promptClause)
        let custom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append(custom)
        }
        if !glossary.isEmpty {
            lines.append("Keep these terms exactly as written, never translate them: \(glossary.joined(separator: ", ")).")
        }
        lines.append("Reply with ONLY the corrected text. No explanations, no quotes, no notes.")
        return lines.joined(separator: "\n")
    }

    /// The full chat for a request. Instructions live ONLY in the system
    /// prompt: a user turn is always data (the text, or the refinement
    /// fields), never directives — a proofreading contract applied to an
    /// instruction-shaped user message makes the model "correct" the
    /// instruction and echo it back.
    public func messages(for request: TranslationRequest) -> [ChatMessage] {
        guard let refinement = request.refinement else {
            let system: String
            switch request.mode {
            case .translate:
                system = systemPrompt(source: request.source, target: request.target,
                                      tone: request.tone,
                                      customInstructions: request.customInstructions,
                                      glossary: request.glossary)
            case .correct:
                system = correctionPrompt(language: request.source, tone: request.tone,
                                          customInstructions: request.customInstructions,
                                          glossary: request.glossary)
            }
            return [.system(system), .user(request.text)]
        }
        return [.system(refinementPrompt(for: request)),
                .user("""
                Original text:
                \(request.text)

                Previous version:
                \(refinement.previousOutput)

                Feedback: \(refinement.feedback)
                """)]
    }

    private func refinementPrompt(for request: TranslationRequest) -> String {
        var lines: [String] = []
        switch request.mode {
        case .translate:
            lines.append("You are a translation engine. The user received the previous version as a translation of the original text from \(request.source.englishName) to \(request.target.englishName) and asked for changes. Write a new \(request.target.englishName) translation of the original text that applies the user's feedback.")
        case .correct:
            lines.append("You are a proofreading engine. The user received the previous version as a corrected form of the original text and asked for changes. Write a new version of the original text — same language (\(request.source.englishName)), same meaning — that fixes grammar, spelling and punctuation and applies the user's feedback.")
        }
        lines.append("Preserve emoji, keyboard shortcuts (like ⌃T), code, URLs, numbers and any other symbols exactly as written — never drop or translate them.")
        lines.append(request.tone.promptClause)
        let custom = request.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            lines.append(custom)
        }
        if !request.glossary.isEmpty {
            lines.append("Keep these terms exactly as written, never translate them: \(request.glossary.joined(separator: ", ")).")
        }
        lines.append("Reply with ONLY the new text. No explanations, no quotes, no labels, no notes.")
        return lines.joined(separator: "\n")
    }
}
