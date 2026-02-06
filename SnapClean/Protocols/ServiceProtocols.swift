import AppKit
import CoreGraphics

// MARK: - Screen Capture Protocol

/// Abstracts screen capture operations for testability.
/// Inject a mock conforming to this protocol in tests.
protocol ScreenCapturing {
    func captureRegion(rect: CGRect) -> NSImage?
    func captureFullScreen() -> NSImage?
    func captureWindow(at point: CGPoint) -> NSImage?
    func captureWindowByID(_ windowID: CGWindowID, bounds: CGRect) -> NSImage?
    func getWindowList() -> [(id: CGWindowID, name: String, bounds: CGRect)]
    func saveImage(_ image: NSImage, to folder: URL?) -> String?
    func copyToClipboard(_ image: NSImage)
    func openInFinder(_ path: String)
}

// Default parameter support for protocol methods
extension ScreenCapturing {
    func saveImage(_ image: NSImage) -> String? {
        saveImage(image, to: nil)
    }
}

// MARK: - History Persistence Protocol

/// Abstracts screenshot history persistence for testability.
/// Inject a mock conforming to this protocol in tests.
protocol HistoryPersisting {
    var saveDirectory: URL { get }
    func saveHistory(_ history: [ScreenshotItem])
    func loadHistory() -> [ScreenshotItem]
    func removeFiles(atPaths paths: [String])
    func isPathAllowed(_ path: String) -> Bool
}

// MARK: - Hotkey Registration Protocol

/// Abstracts global hotkey registration for testability.
protocol HotkeyRegistering {
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void)
    func unregister(keyCode: UInt16)
    func unregisterAll()
}
