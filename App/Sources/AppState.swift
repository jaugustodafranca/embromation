import AppKit
import Combine
import Foundation
import TranslatorCore

@MainActor
final class AppState: ObservableObject {
    let settings = SettingsStore()
    let popup = PopupController()
    lazy var modelStore = ModelStore(settings: settings)
    lazy var translator: StreamingTranslator = MLXTranslator(
        modelID: { SettingsData.snapshot().selectedModelID },
        unloadAfterMinutes: { SettingsData.snapshot().unloadAfterMinutes }
    )
    lazy var coordinator = TranslationCoordinator(settings: settings,
                                                  capture: SelectionCapture(),
                                                  translator: translator,
                                                  popup: popup,
                                                  modelStore: modelStore)

    private var hotkey: HotkeyController?

    var needsOnboarding: Bool { !settings.data.didOnboard }

    func start() {
        guard hotkey == nil else { return } // idempotent: scenePhase fires repeatedly
        hotkey = HotkeyController(
            onTranslate: { [weak self] in self?.coordinator.translateSelection() },
            onCorrect: { [weak self] in self?.coordinator.correctSelection() }
        )
        // Settings persistence is debounced — write any pending edit on quit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak settings] _ in
            MainActor.assumeIsolated { settings?.flush() }
        }
    }
}
