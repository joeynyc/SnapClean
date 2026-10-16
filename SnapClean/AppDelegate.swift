import SwiftUI
import Carbon

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var aboutWindow: NSWindow?
    /// Owned here rather than by a window so global hotkeys work even when the main window was never opened.
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupHotkeys()
        checkScreenRecordingPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }

    private func setupHotkeys() {
        HotkeyManager.shared.register(
            keyCode: UInt16(kVK_F1),
            modifiers: [.command, .shift],
            action: { [weak self] in
                Task { @MainActor in
                    self?.appState.startCapture(mode: .region)
                }
            }
        )

        HotkeyManager.shared.register(
            keyCode: UInt16(kVK_F2),
            modifiers: [.command, .shift],
            action: { [weak self] in
                Task { @MainActor in
                    self?.appState.startCapture(mode: .window)
                }
            }
        )

        HotkeyManager.shared.register(
            keyCode: UInt16(kVK_F3),
            modifiers: [.command, .shift],
            action: { [weak self] in
                Task { @MainActor in
                    self?.appState.startCapture(mode: .screen)
                }
            }
        )
    }

    private func checkScreenRecordingPermission() {
        _ = CGPreflightScreenCaptureAccess()
    }
}
