import AppKit

struct SelectionReplacer {
    /// How long the frontmost app gets to consume the synthetic ⌘V before the
    /// original clipboard is restored.
    private static let pasteSettleDelay: Duration = .milliseconds(250)

    /// Puts `text` on the clipboard, simulates ⌘V into the still-focused app,
    /// then restores the previous clipboard content.
    func replaceSelection(with text: String) async {
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.snapshotItems()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Keystroke.postCommand(Keystroke.v)
        try? await Task.sleep(for: Self.pasteSettleDelay)

        pasteboard.restore(from: snapshot)
    }
}
