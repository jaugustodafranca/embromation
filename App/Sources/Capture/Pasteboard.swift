import AppKit

extension NSPasteboard {
    /// Deep-copies every item and every representation so the clipboard can be
    /// restored later without losing images, RTF, or file references.
    func snapshotItems() -> [NSPasteboardItem] {
        (pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    func restore(from snapshot: [NSPasteboardItem]) {
        clearContents()
        if !snapshot.isEmpty {
            writeObjects(snapshot)
        }
    }
}

/// Synthesizes ⌘-key presses into the frontmost app (requires Accessibility permission).
enum Keystroke {
    /// ANSI-layout virtual key codes — see HIToolbox/Events.h.
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9

    static func postCommand(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
