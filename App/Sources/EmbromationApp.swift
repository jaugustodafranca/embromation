import SwiftUI
import TranslatorCore

@main
struct EmbromationApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            Button(L10n.t("menu.translate")) { state.coordinator.translateSelection() }
                .keyboardShortcut("t", modifiers: [.control])
            Button(L10n.t("menu.fix_grammar")) { state.coordinator.correctSelection() }
                .keyboardShortcut("g", modifiers: [.control])
            Divider()
            SettingsLink { Text(L10n.t("menu.settings")) }
                .keyboardShortcut(",")
            Divider()
            Button(L10n.t("menu.quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onChange(of: scenePhase, initial: true) { _, _ in
            state.start()
            if state.needsOnboarding { openWindow(id: "onboarding") }
        }

        Settings {
            SettingsView(settings: state.settings, modelStore: state.modelStore)
        }

        Window(L10n.t("onboarding.window_title"), id: "onboarding") {
            OnboardingView(settings: state.settings,
                           modelStore: state.modelStore,
                           translator: state.translator) {
                NSApp.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
    }
}
