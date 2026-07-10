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
}
