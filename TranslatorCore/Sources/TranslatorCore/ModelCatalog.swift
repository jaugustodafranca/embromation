public struct ModelSpec: Equatable, Identifiable, Sendable {
    /// Hugging Face repo id, e.g. "mlx-community/Qwen3-4B-4bit".
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

/// Text-only checkpoints ONLY. Multimodal repos (e.g. gemma-3-4b-it) fail to
/// load through MLXLLM's text-model factory — their vision-model config makes
/// the text tower come out with mismatched tensor shapes.
public enum ModelCatalog {
    public static let qwen3_4b = ModelSpec(id: "mlx-community/Qwen3-4B-4bit",
                                           displayName: "Qwen 3 4B", approxSizeGB: 2.3, minRAMGB: 16)
    public static let llama32_3b = ModelSpec(id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                                             displayName: "Llama 3.2 3B", approxSizeGB: 1.8, minRAMGB: 8)
    public static let qwen25_1_5b = ModelSpec(id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                                              displayName: "Qwen 2.5 1.5B (light)", approxSizeGB: 1.0, minRAMGB: 8)
    public static let `default` = qwen3_4b
    public static let all: [ModelSpec] = [qwen3_4b, llama32_3b, qwen25_1_5b]

    /// Unknown ids (e.g. a model removed from the catalog) fall back to the
    /// default — this is what migrates users off a retired model automatically.
    public static func spec(for id: String) -> ModelSpec {
        all.first { $0.id == id } ?? `default`
    }
}
