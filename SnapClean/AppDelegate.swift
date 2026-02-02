import SwiftUI
import Carbon
import ApplicationServices

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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "SnapClean needs screen recording permission to capture screenshots. Please enable it in System Settings > Privacy & Security > Screen Recording."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.security.privacy_screenrecording")!)
            }
        }
    }
}

extension Notification.Name {
    static let startCapture = Notification.Name("startCapture")
    static let openHistory = Notification.Name("openHistory")
}
