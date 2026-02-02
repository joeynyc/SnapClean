import SwiftUI
import Carbon
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var aboutWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupHotkeys()
        checkScreenRecordingPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregisterAll()
    }

    private func setupStatusBar() {
        let statusBar = NSStatusBar.system
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "SnapClean")
        statusItem?.button?.action = #selector(toggleMenu)
        statusItem?.button?.target = self
    }

    @objc private func toggleMenu() {
        if let button = statusItem?.button {
            let menu = NSMenu()
            menu.addItem(withTitle: "Capture Region", action: #selector(captureRegion), keyEquivalent: "1")
            menu.addItem(withTitle: "Capture Window", action: #selector(captureWindow), keyEquivalent: "2")
            menu.addItem(withTitle: "Capture Screen", action: #selector(captureScreen), keyEquivalent: "3")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Open History", action: #selector(openHistory), keyEquivalent: "h")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
            menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")

            statusItem?.menu = menu
            button.performClick(nil)
        }
    }

    @objc private func captureRegion() {
        NotificationCenter.default.post(name: .startCapture, object: nil, userInfo: ["mode": CaptureMode.region])
    }

    @objc private func captureWindow() {
        NotificationCenter.default.post(name: .startCapture, object: nil, userInfo: ["mode": CaptureMode.window])
    }

    @objc private func captureScreen() {
        NotificationCenter.default.post(name: .startCapture, object: nil, userInfo: ["mode": CaptureMode.screen])
    }

    @objc private func openHistory() {
        NotificationCenter.default.post(name: .openHistory, object: nil)
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let preferencesView = PreferencesView()
            preferencesWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: true
            )
            preferencesWindow?.contentView = NSHostingView(rootView: preferencesView)
            preferencesWindow?.title = "Preferences"
            preferencesWindow?.center()
        }
        preferencesWindow?.orderFrontRegardless()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
    static let captureComplete = Notification.Name("captureComplete")
    static let saveScreenshot = Notification.Name("saveScreenshot")
}
