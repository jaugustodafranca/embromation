// App/Sources/Onboarding/OnboardingView.swift
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
                Button(step == 3 ? "Start using" : "Continue", action: advance)
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
        if step == 1 {
            // Triggers the system prompt that lists the app in Accessibility settings.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        if step == 2, modelStore.state != .ready {
            Task { await modelStore.download() }
        }
        if step == 3 {
            runDemo()
        }
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
            Text("Chega de embromation").font(.title2.bold())
            Text("Select text in any app, press the shortcut, and watch the translation appear instantly. Nothing leaves your Mac — no account, no API keys.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private var permission: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield").font(.system(size: 40))
            Text("Accessibility permission").font(.title3.bold())
            Text("macOS requires this permission so Embromation can read the text you select in other apps. It is used for nothing else.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open System Settings…") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            if accessibilityGranted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    private var download: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 40))
            Text("Downloading the model").font(.title3.bold())
            Text("\(modelStore.selectedSpec.displayName) runs entirely on your Mac. One-time download.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if case .downloading(let fraction) = modelStore.state {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))% of ~\(modelStore.selectedSpec.approxSizeGB, specifier: "%.1f") GB")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if modelStore.state == .ready {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let message = modelStore.lastErrorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Try again") { Task { await modelStore.download() } }
            }
        }
    }

    private var done: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal").font(.system(size: 40))
            Text("All set").font(.title3.bold())
            Text("“\(Self.demoSentence)”").italic()
            Text(demoText.isEmpty ? "…" : demoText).bold()
            Text("Select any text and press ⌥⌘T.").foregroundStyle(.secondary)
        }
    }
}
