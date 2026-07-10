import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    // Active only while the popup is on screen — see enable/disable below.
    static let popupCopy = Self("popupCopy", default: .init(.c, modifiers: [.command]))
    static let popupReplace = Self("popupReplace", default: .init(.return, modifiers: [.command]))
}

@MainActor
final class PopupController {
    let model = PopupModel()
    private var panel: PopupPanel?
    private var monitors: [Any] = []
    private var resizeSubscription: AnyCancellable?
    var onDismiss: (() -> Void)?

    init() {
        // Registered hotkeys are consumed by the system, so while the popup is
        // open ⌘C/⌘⏎ act on the translation instead of reaching the host app.
        KeyboardShortcuts.onKeyUp(for: .popupCopy) { [weak self] in
            guard let self, self.model.phase == .done else { return }
            self.model.onCopy?()
        }
        KeyboardShortcuts.onKeyUp(for: .popupReplace) { [weak self] in
            guard let self, self.model.phase == .done else { return }
            self.model.onReplace?()
        }
        KeyboardShortcuts.disable(.popupCopy, .popupReplace)
    }

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: PopupView(model: model))
            panel = PopupPanel(contentView: hosting)
            // Grow the panel as the translation streams in (throttled so the
            // window doesn't jitter on every token).
            resizeSubscription = model.objectWillChange
                .throttle(for: .milliseconds(80), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.resizeToFit()
                        self?.syncShortcutsToPhase()
                    }
                }
        }
        position()
        resizeToFit()
        syncShortcutsToPhase()
        panel?.orderFrontRegardless()
        installMonitors()
    }

    /// ⌘C/⌘⏎ may only exist while a finished translation is on screen.
    /// Enabling them any earlier swallows the capture's own synthetic ⌘C —
    /// the hotkey would eat the copy command before the host app sees it.
    private func syncShortcutsToPhase() {
        if model.phase == .done {
            KeyboardShortcuts.enable(.popupCopy, .popupReplace)
        } else {
            KeyboardShortcuts.disable(.popupCopy, .popupReplace)
        }
    }

    /// Resizes the panel to the SwiftUI content's ideal height, keeping the
    /// top edge anchored so the popup grows downward from the cursor.
    private func resizeToFit() {
        guard let panel, let content = panel.contentView else { return }
        let fitting = content.fittingSize
        let height = min(max(fitting.height, 96), 480)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.size.height - height
        frame.size.height = height
        if let screen = panel.screen ?? NSScreen.main {
            frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY + 8)
        }
        panel.setFrame(frame, display: true)
    }

    func dismiss() {
        KeyboardShortcuts.disable(.popupCopy, .popupReplace)
        removeMonitors()
        panel?.orderOut(nil)
        onDismiss?()
    }

    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - 40, y: mouse.y - panel.frame.height - 16)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
    }

    private static let escapeKeyCode: UInt16 = 53

    /// Esc anywhere or a click outside the panel dismisses it.
    /// Global monitors require the Accessibility permission we already hold.
    private func installMonitors() {
        removeMonitors()
        let clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        let escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            Task { @MainActor in self?.dismiss() }
        }
        monitors = [clickMonitor, escapeMonitor].compactMap { $0 }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
