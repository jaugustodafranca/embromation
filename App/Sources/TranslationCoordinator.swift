// App/Sources/TranslationCoordinator.swift
import AppKit
import TranslatorCore

@MainActor
final class TranslationCoordinator {
    private let settings: SettingsStore
    private let capture: SelectionCapturing
    private let translator: StreamingTranslator
    private let popup: PopupController
    private var currentTask: Task<Void, Never>?
    private var lastCapturedText = ""
    private var pendingClipboardChangeCount: Int?

    init(settings: SettingsStore, capture: SelectionCapturing,
         translator: StreamingTranslator, popup: PopupController) {
        self.settings = settings
        self.capture = capture
        self.translator = translator
        self.popup = popup
        popup.onDismiss = { [weak self] in self?.currentTask?.cancel() }
        popup.model.onRetarget = { [weak self] lang in self?.retarget(lang) }
        popup.model.onRetry = { [weak self] in self?.translateSelection() }
    }

    func translateSelection() {
        currentTask?.cancel()
        currentTask = Task { await run() }
    }

    func retarget(_ language: Language) {
        guard !lastCapturedText.isEmpty else { return }
        currentTask?.cancel()
        let text = lastCapturedText
        currentTask = Task { await stream(text: text, forcedTarget: language) }
    }

    private func run() async {
        popup.model.phase = .working
        popup.model.text = ""
        popup.show()

        guard AXIsProcessTrusted() else {
            popup.model.phase = .permissionNeeded
            return
        }
        var text = await capture.captureSelectedText() ?? ""
        guard !Task.isCancelled else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Two-step fallback (spec §6): only translate the clipboard if it changed
            // since we last showed "no selection" — i.e. the user copied on purpose.
            let pasteboard = NSPasteboard.general
            if let recorded = pendingClipboardChangeCount,
               pasteboard.changeCount != recorded {
                text = pasteboard.string(forType: .string) ?? ""
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pendingClipboardChangeCount = pasteboard.changeCount
                popup.model.phase = .noSelection
                return
            }
        }
        pendingClipboardChangeCount = nil
        lastCapturedText = text
        await stream(text: text, forcedTarget: nil)
    }

    private func stream(text: String, forcedTarget: Language?) async {
        guard !Task.isCancelled else { return }
        let detected = LanguageDetector().detect(text)
        let target = forcedTarget
            ?? LanguagePairResolver().target(forDetected: detected, pair: settings.data.pair)
        let source = detected ?? settings.data.pair.secondary

        popup.model.sourceCode = source.code
        popup.model.target = target
        popup.model.text = ""
        popup.model.phase = .streaming

        let request = TranslationRequest(text: text, source: source, target: target,
                                         tone: settings.data.tone,
                                         customInstructions: settings.data.customInstructions,
                                         glossary: settings.data.glossary)
        do {
            for try await chunk in translator.translate(request) {
                try Task.checkCancellation()
                popup.model.text += chunk
            }
            guard !Task.isCancelled else { return }
            popup.model.phase = .done
        } catch is CancellationError {
            // dismissed or superseded — nothing to do
        } catch {
            popup.model.phase = .failed(error.localizedDescription)
        }
    }
}
