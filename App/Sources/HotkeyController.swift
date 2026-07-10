import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection",
                                         default: .init(.t, modifiers: [.option, .command]))
}

@MainActor
final class HotkeyController {
    init(onTrigger: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) {
            onTrigger()
        }
    }
}
