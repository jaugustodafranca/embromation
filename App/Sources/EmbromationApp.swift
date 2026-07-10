import SwiftUI
import TranslatorCore

/// Menu bar apps aren't activated by default — without explicit handling,
/// reopening from Finder/Dock does nothing and windows open behind others.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopen: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        onReopen?()
        return false
    }
}

@main
struct EmbromationApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            Button(L10n.t("menu.translate")) { state.coordinator.translateSelection() }
                .keyboardShortcut("t", modifiers: [.control])
            Button(L10n.t("menu.fix_grammar")) { state.coordinator.correctSelection() }
                .keyboardShortcut("g", modifiers: [.control])
            Divider()
            Button(L10n.t("menu.welcome_guide")) { showOnboarding() }
            Button(L10n.t("menu.settings")) { showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button(L10n.t("menu.quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onChange(of: scenePhase, initial: true) { _, _ in
            state.start()
            appDelegate.onReopen = {
                if state.needsOnboarding { showOnboarding() } else { showSettings() }
            }
            if state.needsOnboarding { showOnboarding() }
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

    /// Activate first: an LSUIElement app opening a window without activation
    /// leaves it buried behind other apps with no focus.
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }
}
