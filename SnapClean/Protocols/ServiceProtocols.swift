import AppKit
import CoreGraphics

// MARK: - Screen Capture Protocol

/// Abstracts screen capture operations for testability.
/// Inject a mock conforming to this protocol in tests.
protocol ScreenCapturing {
    func captureRegion(rect: CGRect) async -> NSImage?
    func captureFullScreen() async -> NSImage?
    func captureWindowByID(_ windowID: CGWindowID) async -> NSImage?
    func getWindowList() async -> [(id: CGWindowID, name: String, bounds: CGRect)]
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
    func loadHistory() async -> [ScreenshotItem]
    /// Deletes files, skipping any outside the app-owned store (see `isPathAllowed`).
    func removeFiles(atPaths paths: [String])
    /// Moves a file to the Trash; used when the user explicitly deletes a history item.
    func trashFile(atPath path: String)
    func isPathAllowed(_ path: String) -> Bool
}

// MARK: - Hotkey Registration Protocol

/// Abstracts global hotkey registration for testability.
protocol HotkeyRegistering {
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void)
    func unregister(keyCode: UInt16)
    func unregisterAll()
}
