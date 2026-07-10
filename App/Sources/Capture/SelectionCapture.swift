import AppKit
import ApplicationServices

protocol SelectionCapturing: Sendable {
    /// Returns the currently selected text in the frontmost app, or nil.
    func captureSelectedText() async -> String?
}

struct SelectionCapture: SelectionCapturing {
    /// The ⌘C fallback polls the pasteboard every 10ms for up to 300ms.
    private static let pollInterval: Duration = .milliseconds(10)
    private static let maxPollAttempts = 30

    func captureSelectedText() async -> String? {
        if let viaAX = axSelectedText(), !viaAX.isEmpty {
            return viaAX
        }
        return await copyBasedCapture()
    }

    /// Fast path: read kAXSelectedText from the focused UI element. No clipboard involved.
    private func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement // safe: type verified above
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success else {
            return nil
        }
        return selectedRef as? String
    }

    /// Fallback: simulate ⌘C, poll the pasteboard changeCount, restore the clipboard.
    private func copyBasedCapture() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = pasteboard.snapshotItems()
        let startCount = pasteboard.changeCount

        Keystroke.postCommand(Keystroke.c)

        var changed = false
        for _ in 0..<Self.maxPollAttempts {
            try? await Task.sleep(for: Self.pollInterval)
            if pasteboard.changeCount != startCount {
                changed = true
                break
            }
        }
        guard changed else { return nil }
        let captured = pasteboard.string(forType: .string)

        pasteboard.restore(from: snapshot)
        return captured
    }
}
