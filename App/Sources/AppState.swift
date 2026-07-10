import Foundation
import Combine
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
                                                  popup: popup)

    private var hotkey: HotkeyController?

    var needsOnboarding: Bool { !settings.data.didOnboard }

    func start() {
        guard hotkey == nil else { return } // idempotent: scenePhase fires repeatedly
        hotkey = HotkeyController { [weak self] in
            self?.coordinator.translateSelection()
        }
    }
}
