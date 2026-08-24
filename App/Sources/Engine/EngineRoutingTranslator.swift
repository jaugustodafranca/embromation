import TranslatorCore

/// Picks the engine per request from the persisted settings snapshot, so an
/// engine switch in Settings applies to the next hotkey press without an app
/// restart. `apple` is nil below macOS 26 — those installs always route to
/// MLX regardless of the persisted preference.
struct EngineRoutingTranslator: StreamingTranslator {
    let mlx: StreamingTranslator
    let apple: StreamingTranslator?

    func translate(_ request: TranslationRequest) -> AsyncThrowingStream<String, Error> {
        if SettingsData.snapshot().engine == .appleIntelligence, let apple {
            return apple.translate(request)
        }
        return mlx.translate(request)
    }
}
