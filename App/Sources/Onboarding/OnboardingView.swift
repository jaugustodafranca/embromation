import SwiftUI
import ApplicationServices
import TranslatorCore

struct OnboardingView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var modelStore: ModelStore
    let translator: StreamingTranslator
    let dismiss: () -> Void

    @State private var step = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var demoText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Load-bearing joke — see AGENTS.md. Never change this sentence.
    private static let demoSentence = "The book is on the table."

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch step {
                case 0: welcome
                case 1: permission
                case 2: download
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                ForEach(0..<4) { index in
                    Circle().fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
                Spacer()
                Button(step == 3 ? L10n.t("onboarding.start") : L10n.t("onboarding.continue"), action: advance)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            }
        }
        .padding(28)
        .frame(width: 460, height: 360)
        .onReceive(timer) { _ in accessibilityGranted = AXIsProcessTrusted() }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return accessibilityGranted
        case 2: return modelStore.state == .ready
        default: return true
        }
    }

    private func advance() {
        if step == 3 {
            settings.data.didOnboard = true
            dismiss()
            return
        }
        step += 1
        switch step {
        case 1: promptForAccessibility()
        case 2: startDownloadIfNeeded()
        case 3: runDemo()
        default: break
        }
    }

    /// Triggers the system prompt that lists the app in Accessibility settings.
    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func startDownloadIfNeeded() {
        guard modelStore.state != .ready else { return }
        modelStore.download()
    }

    private func runDemo() {
        demoText = ""
        let request = TranslationRequest(text: Self.demoSentence,
                                         source: .english, target: settings.data.pair.primary,
                                         tone: .neutral, customInstructions: "", glossary: [])
        Task {
            do {
                for try await chunk in translator.translate(request) { demoText += chunk }
            } catch {
                demoText = "…" // demo is best-effort; real errors surface in normal use
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            Image(systemName: "character.bubble").font(.system(size: 44))
            Text(L10n.t("onboarding.title")).font(.title2.bold())
            Text(L10n.t("onboarding.welcome_body"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private var permission: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 40))
            Text(L10n.t("onboarding.permission_title")).font(.title3.bold())
            Text(L10n.t("onboarding.permission_body"))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(L10n.t("popup.open_settings")) {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            if accessibilityGranted {
                Label(L10n.t("onboarding.granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text(L10n.t("onboarding.permission_hint"))
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var download: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 40))
            Text(L10n.t("onboarding.download_title")).font(.title3.bold())
            Text(String(format: L10n.t("onboarding.download_body"), modelStore.selectedSpec.displayName))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text(String(format: L10n.t("onboarding.model_suggested"), Int(ModelCatalog.physicalMemoryGB)))
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if case .downloading(let progress) = modelStore.state {
                ProgressView(value: progress)
                Text(String(format: L10n.t("onboarding.downloading_size"),
                            progress * 100, modelStore.selectedSpec.approxSizeGB))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.t("onboarding.cancel_download")) { modelStore.cancelDownload() }
            } else if modelStore.state == .ready {
                Label(L10n.t("onboarding.model_ready"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                if let message = modelStore.lastErrorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
                Button(L10n.t(modelStore.lastErrorMessage == nil ? "settings.download" : "popup.retry")) {
                    modelStore.download()
                }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal").font(.system(size: 40))
            Text(L10n.t("onboarding.ready")).font(.title3.bold())
            Text("“\(Self.demoSentence)”").italic()
            Text(demoText.isEmpty ? "…" : demoText).bold()
            Text(L10n.t("onboarding.hint")).foregroundStyle(.secondary)
        }
    }
}
