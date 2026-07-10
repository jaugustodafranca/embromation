// App/Sources/EmbromationApp.swift
import SwiftUI
import TranslatorCore

@main
struct EmbromationApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Embromation", systemImage: "character.bubble") {
            Button("Debug: capture selection") {
                Task {
                    let text = await SelectionCapture().captureSelectedText()
                    NSLog("[embromation] captured: \(text ?? "<nil>")")
                }
            }
            Divider()
            Button("Quit Embromation") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
