/// The tone applied when fixing grammar/spelling (⌃G), kept separate from the
/// translation `Tone` setting. `.keep` is the default: it preserves whatever
/// tone the input text already has instead of forcing one.
public enum CorrectionTone: String, CaseIterable, Codable, Sendable {
    case keep
    case neutral
    case formal
    case casual

    /// `nil` for `.keep` — no clause is added, so the prompt never asks the
    /// model to both keep and change the tone at once.
    public var promptClause: String? {
        switch self {
        case .keep: return nil
        case .neutral: return Tone.neutral.promptClause
        case .formal: return Tone.formal.promptClause
        case .casual: return Tone.casual.promptClause
        }
    }
}
