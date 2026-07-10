public struct ModelSpec: Equatable, Identifiable, Sendable {
    /// Hugging Face repo id, e.g. "mlx-community/gemma-3-4b-it-4bit".
    public let id: String
    public let displayName: String
    public let approxSizeGB: Double
    public let minRAMGB: Int

    public init(id: String, displayName: String, approxSizeGB: Double, minRAMGB: Int) {
        self.id = id
        self.displayName = displayName
        self.approxSizeGB = approxSizeGB
        self.minRAMGB = minRAMGB
    }
}

public enum ModelCatalog {
    public static let gemma3_4b = ModelSpec(id: "mlx-community/gemma-3-4b-it-4bit",
                                            displayName: "Gemma 3 4B", approxSizeGB: 2.6, minRAMGB: 16)
    public static let qwen3_4b = ModelSpec(id: "mlx-community/Qwen3-4B-4bit",
                                           displayName: "Qwen 3 4B", approxSizeGB: 2.3, minRAMGB: 16)
    public static let qwen25_1_5b = ModelSpec(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                                              displayName: "Qwen 2.5 1.5B (light)", approxSizeGB: 1.0, minRAMGB: 8)
    public static let `default` = gemma3_4b
    public static let all: [ModelSpec] = [gemma3_4b, qwen3_4b, qwen25_1_5b]

    public static func spec(for id: String) -> ModelSpec {
        if let found = all.first(where: { $0.id == id }) {
            return found
        } else {
            return `default`
        }
    }
}
