public enum Tone: String, CaseIterable, Codable, Sendable {
    case neutral
    case formal
    case casual

    public var promptClause: String {
        switch self {
        case .neutral: return "Use a neutral, natural tone."
        case .formal: return "Use a formal, professional tone."
        case .casual: return "Use a casual, conversational tone."
        }
    }
}
