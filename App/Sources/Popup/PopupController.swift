// App/Sources/Popup/PopupController.swift
import AppKit
import SwiftUI

@MainActor
final class PopupController {
    let model = PopupModel()
    private var panel: PopupPanel?
    private var monitors: [Any] = []
    var onDismiss: (() -> Void)?

    func show() {
        if panel == nil {
            let hosting = NSHostingView(rootView: PopupView(model: model))
            panel = PopupPanel(contentView: hosting)
        }
        position()
        panel?.orderFrontRegardless()
        installMonitors()
    }

    func dismiss() {
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

    /// Esc anywhere or a click outside the panel dismisses it.
    /// Global monitors require the Accessibility permission we already hold.
    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        } { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // esc
                Task { @MainActor in self?.dismiss() }
            }
        } { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
