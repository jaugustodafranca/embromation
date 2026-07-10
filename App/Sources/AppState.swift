// App/Sources/AppState.swift
import Foundation
import Combine
import TranslatorCore

@MainActor
final class AppState: ObservableObject {
    let settings = SettingsStore()
    let popup = PopupController()
    // Swapped for MLXTranslator in Task 10.
    let translator: StreamingTranslator = FakeTranslator(wordDelay: .milliseconds(40))
    lazy var coordinator = TranslationCoordinator(settings: settings,
                                                  capture: SelectionCapture(),
                                                  translator: translator,
                                                  popup: popup)
}
