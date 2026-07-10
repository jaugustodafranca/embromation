// App/Sources/Capture/SelectionCapture.swift
import AppKit
import ApplicationServices

protocol SelectionCapturing: Sendable {
    /// Returns the currently selected text in the frontmost app, or nil.
    func captureSelectedText() async -> String?
}

struct SelectionCapture: SelectionCapturing {
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
        let focused = focusedRef as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success else {
            return nil
        }
        return selectedRef as? String
    }

    /// Fallback: simulate ⌘C, poll pasteboard changeCount every 10ms (max 300ms), restore clipboard.
    private func copyBasedCapture() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let startCount = pasteboard.changeCount

        postKeystroke(keyCode: 8, flags: .maskCommand) // 8 = "c"

        var changed = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(10))
            if pasteboard.changeCount != startCount {
                changed = true
                break
            }
        }
        guard changed else { return nil }
        let captured = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }
        return captured
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
