// App/Sources/Capture/SelectionReplacer.swift
import AppKit

struct SelectionReplacer {
    /// Puts `text` on the clipboard, simulates ⌘V into the still-focused app,
    /// then restores the previous clipboard content.
    func replaceSelection(with text: String) async {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboardItems(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postKeystroke(keyCode: 9, flags: .maskCommand) // 9 = "v"
        try? await Task.sleep(for: .milliseconds(250))  // let the app consume the paste

        pasteboard.clearContents()
        if !snapshot.isEmpty {
            pasteboard.writeObjects(snapshot)
        }
    }

    private func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
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
