import Foundation
import TranslatorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Gate for the OS-managed Apple Intelligence model (FoundationModels,
/// macOS 26+). The app deploys to macOS 14, so every touch point goes
/// through here and stays behind availability checks.
enum AppleIntelligenceEngine {
    /// Whether this OS can offer the engine at all — independent of whether
    /// Apple Intelligence is actually enabled in System Settings.
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// `nil` when the model can serve requests right now; otherwise a
    /// user-facing reason (device, setting, or model still preparing).
    static var unavailabilityMessage: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return L10n.t("settings.engine_apple_not_enabled")
            case .unavailable(.deviceNotEligible):
                return L10n.t("settings.engine_apple_not_eligible")
            case .unavailable(.modelNotReady):
                return L10n.t("settings.engine_apple_not_ready")
            case .unavailable:
                return L10n.t("settings.engine_apple_unavailable")
            }
        }
        #endif
        return L10n.t("settings.engine_apple_requires_macos26")
    }

    /// `nil` below macOS 26 — callers fall back to the MLX engine.
    static func makeTranslator() -> StreamingTranslator? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleFMTranslator() }
        #endif
        return nil
    }
}

struct AppleEngineUnavailableError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Apple Intelligence's system guardrails declined the text. The filter is
/// notoriously over-sensitive (it refuses ordinary work messages), so the
/// coordinator treats this as retriable on the local MLX engine.
struct AppleGuardrailError: LocalizedError {
    var errorDescription: String? { L10n.t("popup.apple_guardrail") }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct AppleFMTranslator: StreamingTranslator {
    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.run(request) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(_ request: TranslationRequest,
                            yield: @escaping @Sendable (String) -> Void) async throws {
        // Fail with the same message Settings shows (e.g. Apple Intelligence
        // turned off after the engine was selected) instead of an opaque
        // framework error from the session call.
        if let message = AppleIntelligenceEngine.unavailabilityMessage {
            throw AppleEngineUnavailableError(message: message)
        }
        let messages = PromptBuilder().messages(for: request)
        let instructions = messages.first { $0.role == .system }?.content ?? ""
        let prompt = messages.first { $0.role == .user }?.content ?? request.text
        // Mirrors MLXTranslator's sampling intent. No thinking mode exists
        // here, so correction can keep the near-greedy temperature that
        // proofreading wants without the Qwen3 repetition hazard.
        let temperature: Double
        if request.refinement != nil {
            temperature = 0.7
        } else if request.mode == .correct {
            temperature = 0.2
        } else {
            temperature = 0.3
        }
        // A fresh session per request: hotkey invocations are independent —
        // context carries over via the prompt (refinement), never the session.
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: temperature, maximumResponseTokens: 2048)
        // FoundationModels streams cumulative snapshots; the protocol
        // promises incremental chunks — CumulativeStreamDelta converts.
        var delta = CumulativeStreamDelta()
        do {
            let stream = session.streamResponse(to: prompt, options: options)
            for try await snapshot in stream {
                try Task.checkCancellation()
                if let chunk = delta.consume(snapshot.content) {
                    yield(chunk)
                }
            }
        } catch let error as LanguageModelSession.GenerationError {
            // Surface guardrail refusals as a typed, retriable error — the
            // raw description ("Detected content likely to be unsafe") reads
            // as an accusation on perfectly ordinary work messages.
            if case .guardrailViolation = error {
                throw AppleGuardrailError()
            }
            throw error
        }
    }
}
#endif
