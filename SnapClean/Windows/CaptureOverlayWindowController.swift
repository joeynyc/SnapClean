import SwiftUI
import QuartzCore

final class CaptureOverlayWindowController {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private weak var appState: AppState?

    func show(mode: CaptureMode, appState: AppState) {
        hide()
        self.appState = appState
        installEscapeMonitorIfNeeded()

        let screens = NSScreen.screens
        // The primary display (menu bar) is the one at the Cocoa origin; NSScreen.screens[0] by documentation.
        let primaryScreenHeight = (screens.first { $0.frame.origin == .zero } ?? screens.first)?.frame.height ?? 0

        for screen in screens {
            // With a `screen:` argument, `contentRect` is interpreted relative to that screen's origin,
            // so start at .zero and then place the window on the screen's global frame explicitly.
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: screen.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(screen.frame, display: false)

            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.sharingType = .none

            // The overlay's own frame in display space (top-left origin), used to map overlay-local
            // SwiftUI coordinates to the global display space ScreenCaptureKit uses.
            let overlayDisplayFrame = CaptureGeometry.displayRect(
                fromCocoa: window.frame,
                primaryScreenHeight: primaryScreenHeight
            )

            let rootView = CaptureOverlay(
                mode: mode,
                overlayDisplayFrame: overlayDisplayFrame,
                primaryScreenHeight: primaryScreenHeight
            )
            .environment(appState)
            window.contentView = NSHostingView(rootView: rootView)

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        if mode == .region {
            NSCursor.crosshair.set()
        }
    }

    func hide() {
        let wasShowing = !windows.isEmpty
        for window in windows {
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        CATransaction.flush()
        removeEscapeMonitor()
        appState = nil
        if wasShowing {
            NSCursor.arrow.set()
        }
    }

    private func installEscapeMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // ESC
                Task { @MainActor [weak self] in
                    self?.appState?.cancelCapture()
                }
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    deinit {
        removeEscapeMonitor()
    }
}
