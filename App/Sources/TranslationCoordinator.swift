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
    private var lastRequest: TranslationRequest?
    private var pendingClipboardChangeCount: Int?

    init(settings: SettingsStore, capture: SelectionCapturing,
         translator: StreamingTranslator, popup: PopupController) {
        self.settings = settings
        self.capture = capture
        self.translator = translator
        self.popup = popup
        popup.onDismiss = { [weak self] in self?.currentTask?.cancel() }
        popup.model.onRetarget = { [weak self] lang in self?.retarget(lang) }
        popup.model.onRetry = { [weak self] in
            guard let self else { return }
            if self.popup.model.isCorrection {
                self.correctSelection()
            } else {
                self.translateSelection()
            }
        }
        popup.model.onRefine = { [weak self] feedback in self?.refine(feedback) }
        popup.model.onCopy = { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(self.popup.model.text, forType: .string)
            self.popup.dismiss()
        }
        popup.model.onReplace = { [weak self] in
            guard let self else { return }
            let translation = self.popup.model.text
            self.popup.dismiss()
            Task { await SelectionReplacer().replaceSelection(with: translation) }
        }
    }

    func translateSelection() {
        currentTask?.cancel()
        currentTask = Task { await run(mode: .translate) }
    }

    func correctSelection() {
        currentTask?.cancel()
        currentTask = Task { await run(mode: .correct) }
    }

    func refine(_ feedback: String) {
        guard var request = lastRequest, popup.model.phase == .done else { return }
        request.refinement = Refinement(previousOutput: popup.model.text, feedback: feedback)
        currentTask?.cancel()
        let req = request
        currentTask = Task { await stream(req) }
    }

    func retarget(_ language: Language) {
        guard !lastCapturedText.isEmpty else { return }
        let detected = LanguageDetector().detect(lastCapturedText)
        let source = detected ?? settings.data.pair.secondary
        let request = TranslationRequest(text: lastCapturedText, source: source, target: language,
                                         tone: settings.data.tone,
                                         customInstructions: settings.data.customInstructions,
                                         glossary: settings.data.glossary,
                                         mode: .translate)
        currentTask?.cancel()
        currentTask = Task { await stream(request) }
    }

    private func run(mode: TranslationMode) async {
        // Direct-replace correction never shows the popup while capturing —
        // it only surfaces if something goes wrong (see AX guard / directCorrect).
        let direct = mode == .correct && settings.data.correctionReplacesDirectly
        // Set up-front (not just inside stream()/directCorrect()) so an early
        // return (no selection / no permission) doesn't leave a stale value
        // from a previous run's mode on screen.
        popup.model.isCorrection = (mode == .correct)
        if !direct {
            popup.model.phase = .working
            popup.model.text = ""
            popup.show()
        } else {
            // Direct mode shows the popup only on failure — hide any stale
            // panel and reset presentation state (phase change also disables
            // the popup shortcuts).
            popup.hide()
            popup.model.phase = .working
            popup.model.sourceCode = ""
            popup.model.text = ""
        }

        guard AXIsProcessTrusted() else {
            popup.model.phase = .permissionNeeded
            popup.show()
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
                popup.show()
                return
            }
        }
        pendingClipboardChangeCount = nil
        lastCapturedText = text

        let detected = LanguageDetector().detect(text)
        let source: Language
        let target: Language
        switch mode {
        case .translate:
            target = LanguagePairResolver().target(forDetected: detected, pair: settings.data.pair)
            source = detected ?? settings.data.pair.secondary
        case .correct:
            source = detected ?? settings.data.pair.primary
            target = source
        }
        let request = TranslationRequest(text: text, source: source, target: target,
                                         tone: settings.data.tone,
                                         customInstructions: settings.data.customInstructions,
                                         glossary: settings.data.glossary,
                                         mode: mode)
        if direct {
            await directCorrect(request)
        } else {
            await stream(request)
        }
    }

    private func stream(_ request: TranslationRequest) async {
        guard !Task.isCancelled else { return }
        lastRequest = request
        popup.model.isCorrection = (request.mode == .correct)
        popup.model.sourceCode = request.source.code
        popup.model.target = request.target
        popup.model.text = ""
        // Stay in .working (spinner) until the first chunk arrives — model
        // load and prompt processing take seconds on a cold start, and a
        // blank streaming body reads as frozen.
        popup.model.phase = .working

        do {
            for try await chunk in translator.translate(request) {
                try Task.checkCancellation()
                if popup.model.phase != .streaming {
                    popup.model.phase = .streaming
                }
                popup.model.text += chunk
            }
            guard !Task.isCancelled else { return }
            if popup.model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                popup.model.phase = .failed(L10n.t("popup.empty_response"))
            } else {
                popup.model.phase = .done
            }
        } catch is CancellationError {
            // dismissed or superseded — nothing to do
        } catch {
            popup.model.phase = .failed(error.localizedDescription)
        }
    }

    private func directCorrect(_ request: TranslationRequest) async {
        var result = ""
        do {
            for try await chunk in translator.translate(request) {
                try Task.checkCancellation()
                result += chunk
            }
        } catch is CancellationError {
            return
        } catch {
            popup.model.isCorrection = true
            popup.model.sourceCode = request.source.code
            popup.model.phase = .failed(error.localizedDescription)
            popup.show()
            return
        }
        guard !Task.isCancelled else { return }
        let corrected = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else {
            popup.model.isCorrection = true
            popup.model.sourceCode = request.source.code
            popup.model.phase = .failed(L10n.t("popup.empty_response"))
            popup.show()
            return
        }
        lastRequest = request
        // hide(), not dismiss(): onDismiss cancels currentTask — which is the
        // task running THIS function; cancelling it collapses the replace
        // settle delay and races the clipboard restore against the paste.
        popup.hide()
        // Detached so a superseding run's cancel can't collapse the paste
        // settle delay (same shape as onReplace).
        await Task { await SelectionReplacer().replaceSelection(with: corrected) }.value
    }
}
