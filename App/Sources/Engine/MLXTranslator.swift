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
            // enable_thinking stays off in every mode. With it on, Qwen3
            // writes 300–2 300 hidden reasoning tokens before the answer —
            // at ~80 tok/s that is 5–30 s with nothing on screen, because
            // ThinkBlockFilter withholds everything until </think> closes.
            // Measured on 2026-09-11 against the v1.2.0–v1.3.0 correction
            // path: the reasoning pass fixed one extra error class
            // (agreement with a distant subject) on one of four inputs, at
            // 5–13× the latency. The filter below stays as a guard in case a
            // model emits the tags anyway.
            let enableThinking = false
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
            // it. Correction decodes greedily: proofreading has one right
            // answer and the same input must yield the same fix every time
            // (without thinking there is no repetition hazard). Translation
            // keeps a little sampling room.
            let temperature: Float
            if request.refinement != nil {
                temperature = 0.7
            } else if request.mode == .correct {
                temperature = 0.0
            } else {
                temperature = 0.3
            }
            // Sized for a direct answer: output is at most about as long as
            // the input, and 2048 tokens is roughly 1 500 words.
            let parameters = GenerateParameters(maxTokens: 2048, temperature: temperature, topP: 1.0)
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
