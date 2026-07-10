// App/Sources/EmbromationApp.swift
import SwiftUI
import TranslatorCore

@main
struct EmbromationApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            Button("Translate selection") { state.coordinator.translateSelection() }
            Divider()
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Embromation") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .onChange(of: scenePhase, initial: true) { _, _ in
            state.start()
            if state.needsOnboarding { openWindow(id: "onboarding") }
        }

        Settings {
            SettingsView(settings: state.settings, modelStore: state.modelStore)
        }

        Window("Welcome to Embromation", id: "onboarding") {
            OnboardingView(settings: state.settings,
                           modelStore: state.modelStore,
                           translator: state.translator) {
                NSApp.keyWindow?.close()
            }
        }
        .windowResizability(.contentSize)
    }
}
