import SwiftUI
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupHotkeys()
        checkScreenRecordingPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }

    private func captureRegion() {
        NotificationCenter.default.post(name: .startCapture, object: nil, userInfo: ["mode": CaptureMode.region])
    }

    private func captureWindow() {
        NotificationCenter.default.post(name: .startCapture, object: nil, userInfo: ["mode": CaptureMode.window])
    }

    private func captureScreen() {
        NotificationCenter.default.post(name: .startCapture, object: nil, userInfo: ["mode": CaptureMode.screen])
    }

    private func setupHotkeys() {
        HotkeyManager.shared.register(
            keyCode: UInt16(kVK_F1),
            modifiers: [],
            action: { [weak self] in
                self?.captureRegion()
            }
        )

        HotkeyManager.shared.register(
            keyCode: UInt16(kVK_F2),
            modifiers: [],
            action: { [weak self] in
                self?.captureWindow()
            }
        )

        HotkeyManager.shared.register(
            keyCode: UInt16(kVK_F3),
            modifiers: [],
            action: { [weak self] in
                self?.captureScreen()
            }
        )
    }

    private func checkScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }
}

extension Notification.Name {
    static let startCapture = Notification.Name("startCapture")
    static let openHistory = Notification.Name("openHistory")
}
