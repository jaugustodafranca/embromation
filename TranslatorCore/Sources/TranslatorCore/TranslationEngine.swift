import Foundation

/// Which inference engine serves translation/correction requests.
/// `.mlx` is the downloaded local model; `.appleIntelligence` is the
/// OS-managed Apple Intelligence model (macOS 26+, no download).
public enum TranslationEngine: String, CaseIterable, Codable, Sendable {
    case mlx
    case appleIntelligence
}

/// Converts a cumulative snapshot stream (each element is the full text so
/// far — how Apple's FoundationModels streams) into the incremental chunks
/// `StreamingTranslator` promises.
public struct CumulativeStreamDelta: Sendable {
    private var seen = ""

    public init() {}

    /// Feed one snapshot; returns the not-yet-emitted suffix, if any.
    /// Snapshots should be monotonic; if one ever rewrites earlier text,
    /// the new value becomes the baseline and nothing is emitted — re-sending
    /// from scratch would duplicate text the user already saw.
    public mutating func consume(_ snapshot: String) -> String? {
        defer { seen = snapshot }
        guard snapshot.hasPrefix(seen) else { return nil }
        let suffix = snapshot.dropFirst(seen.count)
        return suffix.isEmpty ? nil : String(suffix)
    }
}
