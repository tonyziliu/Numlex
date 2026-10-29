import AppKit
import SwiftUI

/// The floating panel the global hotkey opens. It becomes key without
/// activating the app, so typing goes to the search field and the app
/// the user was in stays frontmost.
private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the floating clipboard panel the global hotkey toggles.
@MainActor
final class ClipboardPopupController {
    private let model: AppModel
    private let store: ClipboardStore
    private var panel: ClipboardPanel?
    private var resignObserver: NSObjectProtocol?

    init(model: AppModel, store: ClipboardStore) {
        self.model = model
        self.store = store
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { show() }
    }

    private func show() {
        let panel = ClipboardPanel(contentRect: NSRect(origin: .zero, size: ClipboardPopupView.size),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            ClipboardPopupView(model: model, store: store, onDone: { [weak self] in self?.close() })
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
        position(panel)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Centered under the pointer, clamped to the screen it is on.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        let x = min(max(mouse.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let y = min(max(mouse.y - size.height, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
