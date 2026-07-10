import Foundation

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
}
