import Foundation
import MLXLMCommon
import MLXLLM
import TranslatorCore

/// Loads the model lazily, keeps it resident, unloads after an idle period.
actor MLXTranslator: StreamingTranslator {
    private let modelID: @Sendable () -> String
    private let unloadAfterMinutes: @Sendable () -> Int
    private var container: ModelContainer?
    private var containerModelID: String?
    private var idleEpoch = 0

    init(modelID: @escaping @Sendable () -> String,
         unloadAfterMinutes: @escaping @Sendable () -> Int) {
        self.modelID = modelID
        self.unloadAfterMinutes = unloadAfterMinutes
    }

    nonisolated func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: TranslationRequest,
                     yield: @escaping @Sendable (String) -> Void) async throws {
        let container = try await loadedContainer()
        let messages = PromptBuilder().messages(for: request)
        try await container.perform { (context: ModelContext) in
            // enable_thinking: translation must answer directly — chain-of-
            // thought would eat the token budget and the user's time, and
            // there's little to reason about. Correction is the opposite: a
            // small model asked to fix grammar in one shot tends to judge
            // technical/casual text "fine" and change nothing, especially
            // with code-like tokens (camelCase, @mentions) in the mix — a
            // reasoning pass first measurably reduces that no-op behavior.
            // Either way the filter below strips the <think> block (empty or
            // not) before anything reaches the user.
            let enableThinking = request.mode == .correct
            let chat: [Chat.Message] = messages.map { message in
                switch message.role {
                case .system: .system(message.content)
                case .user: .user(message.content)
                }
            }
            let input = try await context.processor.prepare(
                input: UserInput(chat: chat, additionalContext: ["enable_thinking": enableThinking]))
            // Refinements need a higher temperature: with the previous output
            // in the chat, low temperature anchors the model into repeating
            // it. Corrections (first pass) get a lower temperature and a
            // tighter topP than translation — proofreading has one right
            // answer, and cutting the tail of the sampling distribution
            // makes the model less likely to leave a caught error unedited.
            let temperature: Float
            let topP: Float
            if request.refinement != nil {
                (temperature, topP) = (0.7, 1.0)
            } else if request.mode == .correct {
                (temperature, topP) = (0.2, 0.9)
            } else {
                (temperature, topP) = (0.3, 1.0)
            }
            // Thinking spends part of the budget on the reasoning trace
            // before the answer even starts — 2048 was sized for a direct
            // answer only. Without headroom, a long paste-correction could
            // exhaust the budget mid-<think>, and ThinkBlockFilter withholds
            // everything until </think> closes — the user would see an
            // empty result instead of a slow-but-correct one.
            let maxTokens = enableThinking ? 4096 : 2048
            let parameters = GenerateParameters(maxTokens: maxTokens, temperature: temperature, topP: topP)
            let stream = try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
            var filter = ThinkBlockFilter()
            for await generation in stream {
                try Task.checkCancellation()
                if case .chunk(let text) = generation,
                   let visible = filter.filter(text) {
                    yield(visible)
                }
            }
            if let tail = filter.finish() {
                yield(tail)
            }
        }
        scheduleIdleUnload()
    }

    private func loadedContainer() async throws -> ModelContainer {
        let id = modelID()
        if let container, containerModelID == id { return container }
        container = nil // release old model before loading a different one
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: ModelStore.downloader,
            using: ModelStore.tokenizerLoader,
            configuration: ModelConfiguration(id: id)
        ) { _ in }
        container = loaded
        containerModelID = id
        return loaded
    }

    /// Frees ~2.5GB of RAM after the configured idle period (spec §4.2).
    private func scheduleIdleUnload() {
        idleEpoch += 1
        let epoch = idleEpoch
        let minutes = max(1, unloadAfterMinutes())
        Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            await self.unloadIfIdle(since: epoch)
        }
    }

    private func unloadIfIdle(since epoch: Int) {
        guard epoch == idleEpoch else { return }
        container = nil
        containerModelID = nil
    }
}
