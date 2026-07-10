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
        let builder = PromptBuilder()
        let system: String
        switch request.mode {
        case .translate:
            system = builder.systemPrompt(source: request.source,
                                          target: request.target,
                                          tone: request.tone,
                                          customInstructions: request.customInstructions,
                                          glossary: request.glossary)
        case .correct:
            system = builder.correctionPrompt(language: request.source,
                                              tone: request.tone,
                                              customInstructions: request.customInstructions,
                                              glossary: request.glossary)
        }
        try await container.perform { (context: ModelContext) in
            // enable_thinking=false: reasoning models (Qwen3) must answer
            // directly — chain-of-thought would eat the token budget and the
            // user's time. The filter below strips the empty <think/> pair
            // the template still emits.
            var chat: [Chat.Message] = [.system(system), .user(request.text)]
            if let refinement = request.refinement {
                chat.append(.assistant(refinement.previousOutput))
                chat.append(.user("The previous version was not good enough. Feedback: \(refinement.feedback). Rewrite it applying the feedback. Reply with ONLY the new text, in the same language as before."))
            }
            let input = try await context.processor.prepare(
                input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
            // Refinements need a higher temperature: with the previous output
            // in the chat, low temperature anchors the model into repeating it.
            let temperature: Float = request.refinement == nil ? 0.3 : 0.7
            let parameters = GenerateParameters(maxTokens: 2048, temperature: temperature)
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
