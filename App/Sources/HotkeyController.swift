import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translateSelection = Self("translateSelection",
                                         default: .init(.t, modifiers: [.control]))
    static let fixGrammar = Self("fixGrammar",
                                 default: .init(.g, modifiers: [.control]))
}

@MainActor
final class HotkeyController {
    init(onTranslate: @escaping @MainActor () -> Void,
         onCorrect: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .translateSelection) { onTranslate() }
        KeyboardShortcuts.onKeyUp(for: .fixGrammar) { onCorrect() }
    }
}
