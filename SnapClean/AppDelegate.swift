import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here rather than by a window so global hotkeys work even when the main window was never opened.
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.onHotkeysChanged = { [weak self] in
            self?.registerHotkeys()
        }
        registerHotkeys()
        checkScreenRecordingPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }

    private func registerHotkeys() {
        HotkeyManager.shared.unregisterAll()
        guard !appState.isRecordingShortcut else { return }

        for mode in CaptureMode.allCases {
            let shortcut = appState.shortcut(for: mode)
            HotkeyManager.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                Task { @MainActor in
                    self?.appState.startCapture(mode: mode)
                }
            }
        }
    }

    private func checkScreenRecordingPermission() {
        _ = CGPreflightScreenCaptureAccess()
    }
}
