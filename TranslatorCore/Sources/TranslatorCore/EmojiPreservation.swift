/// Small language models sometimes drop or truncate emoji, and flags are the
/// worst case: 🇧🇷 is two regional-indicator scalars, and a tokenizer can emit
/// only the first one. This check finds emoji from the input that are missing
/// in the output so callers can ask the user to review instead of silently
/// shipping a mangled result.
public enum EmojiPreservation {
    /// Distinct emoji clusters present in `input` but absent from `output`.
    public static func missingEmoji(input: String, output: String) -> Set<Character> {
        let wanted = Set(input.filter(isEmojiCluster))
        guard !wanted.isEmpty else { return [] }
        let produced = Set(output.filter(isEmojiCluster))
        return wanted.subtracting(produced)
    }

    private static func isEmojiCluster(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }

    /// A single regional indicator is always a broken half-flag (🇧 instead
    /// of 🇧🇷) and renders as a boxed letter.
    private static func isLoneRegionalIndicator(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1
            && (0x1F1E6...0x1F1FF).contains(character.unicodeScalars.first!.value)
    }

    /// Deterministic cleanup for the two failure shapes small models produce:
    /// half-flags anywhere, and dropped emoji at the end of the text. Middle
    /// emoji can't be repositioned safely, so they are left to the caller's
    /// missing-emoji check.
    public static func repair(input: String, output: String) -> String {
        var repaired = String(output.filter { !isLoneRegionalIndicator($0) })

        let trailingRun = trailingEmojiRun(of: input)
        guard !trailingRun.isEmpty else { return repaired }
        let produced = Set(repaired.filter(isEmojiCluster))
        let missing = trailingRun.filter { !produced.contains($0) }
        guard !missing.isEmpty else { return repaired }

        while let last = repaired.last, last.isWhitespace {
            repaired.removeLast()
        }
        return repaired + " " + String(missing)
    }

    /// The run of emoji clusters at the end of the text, ignoring whitespace
    /// between them (e.g. "obrigado! 🎉 🇧🇷" yields [🎉, 🇧🇷]).
    private static func trailingEmojiRun(of text: String) -> [Character] {
        var run: [Character] = []
        for character in text.reversed() {
            if character.isWhitespace { continue }
            guard isEmojiCluster(character) else { break }
            run.insert(character, at: 0)
        }
        return run
    }
}
