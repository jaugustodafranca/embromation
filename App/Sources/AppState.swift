// App/Sources/AppState.swift
import Foundation
import TranslatorCore

@MainActor
final class AppState: ObservableObject {
    let settings = SettingsStore()
    // Swapped for MLXTranslator in Task 10.
    let translator: StreamingTranslator = FakeTranslator(wordDelay: .milliseconds(40))
}
