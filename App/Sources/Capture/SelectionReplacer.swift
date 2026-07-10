// App/Sources/Capture/SelectionReplacer.swift
import AppKit

struct SelectionReplacer {
    /// Puts `text` on the clipboard, simulates ⌘V into the still-focused app,
    /// then restores the previous clipboard content.
    func replaceSelection(with text: String) async {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postKeystroke(keyCode: 9, flags: .maskCommand) // 9 = "v"
        try? await Task.sleep(for: .milliseconds(250))  // let the app consume the paste

        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }
    }

    private func postKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
