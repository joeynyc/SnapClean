import SwiftUI
import ScreenCaptureKit

// MARK: - CaptureState

@Observable @MainActor
final class CaptureState {
    var isCapturing = false
    var currentCaptureMode: CaptureMode = .region
    var capturedImage: NSImage?
    var showAnnotationCanvas = false
    var captureCountdown: Int = 0
    private(set) var screenCapturePermissionStatus: ScreenCapturePermissionStatus = .unknown
    var lastCaptureError: CaptureError?

    let screenCapture: ScreenCapturing
    @ObservationIgnored let captureOverlayController = CaptureOverlayWindowController()
    @ObservationIgnored private let screenCaptureAccessPromptedKey = "didPromptScreenCaptureAccess"
    @ObservationIgnored var wasMainWindowVisibleBeforeCapture = false
    @ObservationIgnored weak var mainWindow: NSWindow?
    /// Opens the main window scene when no main window exists yet; set from a SwiftUI view that has `openWindow`.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    init(screenCapture: ScreenCapturing = ScreenCaptureService()) {
        self.screenCapture = screenCapture
    }

    func endCapture(showMainWindow: Bool) {
        isCapturing = false
        captureCountdown = 0
        captureOverlayController.hide()
        if showMainWindow {
            revealMainWindow()
        }
    }

    func revealMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }

    func refreshScreenCapturePermissionStatus() {
        if currentScreenCaptureAccess() {
            screenCapturePermissionStatus = .granted
            clearPermissionError()
            return
        }

        guard UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) else {
            screenCapturePermissionStatus = .unknown
            return
        }

        screenCapturePermissionStatus = .checking
        Task { @MainActor in
            let hasAccess = await reconcileScreenCaptureAccessWithScreenCaptureKit()
            if !Task.isCancelled && !hasAccess {
                screenCapturePermissionStatus = .denied
            }
        }
    }

    func recheckScreenCapturePermissionStatus() {
        screenCapturePermissionStatus = .checking
        Task { @MainActor in
            if await hasUsableScreenCaptureAccess() {
                return
            }

            screenCapturePermissionStatus = UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey)
                ? .denied
                : .unknown
        }
    }

    func openScreenCaptureSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        _ = NSWorkspace.shared.open(settingsURL)
    }

    func currentScreenCaptureAccess() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    func hasUsableScreenCaptureAccess() async -> Bool {
        if currentScreenCaptureAccess() {
            screenCapturePermissionStatus = .granted
            clearPermissionError()
            return true
        }

        if UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) {
            screenCapturePermissionStatus = .checking
        }
        return await reconcileScreenCaptureAccessWithScreenCaptureKit()
    }

    private func reconcileScreenCaptureAccessWithScreenCaptureKit() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let hasUsableContent = !content.displays.isEmpty
            if hasUsableContent {
                screenCapturePermissionStatus = .granted
                clearPermissionError()
            }
            return hasUsableContent
        } catch {
            appLogger.error("ScreenCaptureKit permission check failed: \(error.localizedDescription, privacy: .private)")
            if UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) {
                screenCapturePermissionStatus = .denied
            }
            return false
        }
    }

    func requestScreenCaptureAccess() -> Bool {
        UserDefaults.standard.set(true, forKey: screenCaptureAccessPromptedKey)
        let granted = CGRequestScreenCaptureAccess()
        screenCapturePermissionStatus = granted ? .granted : .denied
        if granted {
            clearPermissionError()
        }
        return granted
    }

    func revealMainWindowForPermissionGuidance() {
        revealMainWindow()
    }

    /// Permission checks run on every app activation, so they may only clear the error they own;
    /// a capture or save failure must stay until the user dismisses it.
    private func clearPermissionError() {
        if lastCaptureError == .permissionDenied {
            lastCaptureError = nil
        }
    }
}
