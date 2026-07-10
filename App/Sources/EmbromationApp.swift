// App/Sources/EmbromationApp.swift
import SwiftUI
import TranslatorCore

@main
struct EmbromationApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            Button("Translate selection") {}
                .disabled(true) // wired in Task 8
            Divider()
            Button("Quit Embromation") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
