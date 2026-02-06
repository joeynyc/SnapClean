import SwiftUI

final class CaptureOverlayWindowController {
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private weak var appState: AppState?

    func show(mode: CaptureMode, appState: AppState) {
        hide()
        self.appState = appState
        installEscapeMonitorIfNeeded()

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.sharingType = .none

            let rootView = CaptureOverlay(mode: mode)
                .environmentObject(appState)
            window.contentView = NSHostingView(rootView: rootView)

            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        removeEscapeMonitor()
        appState = nil
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
