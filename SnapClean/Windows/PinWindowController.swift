import SwiftUI

/// Hosts the pinned screenshot in a floating panel that stays above other apps' windows.
@MainActor
final class PinWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    /// Called when the user closes the panel from its title bar.
    var onClose: (() -> Void)?

    func show(image: NSImage, appState: AppState) {
        let isNewPanel = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(rootView: PinWindow().environment(appState))
        panel.setContentSize(contentSize(for: image, on: NSScreen.main))
        if isNewPanel {
            panel.center()
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard panel != nil else { return }
        panel = nil
        onClose?()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Pinned Screenshot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 240, height: 180)
        panel.delegate = self
        return panel
    }

    /// Shows the image at its native size, shrunk to fit within 60% of the screen.
    private func contentSize(for image: NSImage, on screen: NSScreen?) -> NSSize {
        let bounds = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let maxSize = NSSize(width: bounds.width * 0.6, height: bounds.height * 0.6)
        guard image.size.width > 0, image.size.height > 0 else { return maxSize }

        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        return NSSize(
            width: max(image.size.width * scale, 240),
            height: max(image.size.height * scale, 180)
        )
    }
}
