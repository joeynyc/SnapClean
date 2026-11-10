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
    /// Same as `saveImage(_:to:)` but encodes and writes off the calling actor.
    func saveImageInBackground(_ image: NSImage, to folder: URL?) async -> String?
    /// Same as `copyToClipboard(_:)` but encodes off the calling actor.
    func copyToClipboardInBackground(_ image: NSImage) async
    func openInFinder(_ path: String)
}

// Default parameter support for protocol methods
extension ScreenCapturing {
    func saveImage(_ image: NSImage) -> String? {
        saveImage(image, to: nil)
    }

    // Defaults for conformers (e.g. test mocks) that have no background path.
    func saveImageInBackground(_ image: NSImage, to folder: URL?) async -> String? {
        saveImage(image, to: folder)
    }

    func copyToClipboardInBackground(_ image: NSImage) async {
        copyToClipboard(image)
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
    /// Location of an item's JPEG thumbnail inside the store's `Thumbnails/` folder.
    func thumbnailURL(for id: UUID) -> URL
    /// Writes an item's thumbnail file; returns once it is on disk.
    func saveThumbnail(_ data: Data, for id: UUID) async
    func removeThumbnails(for ids: [UUID])
}

extension HistoryPersisting {
    // Defaults for conformers (e.g. test mocks) that keep no thumbnails.
    func thumbnailURL(for id: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SnapCleanThumbnails/\(id.uuidString).jpg")
    }
    func saveThumbnail(_ data: Data, for id: UUID) async {}
    func removeThumbnails(for ids: [UUID]) {}
}

// MARK: - Hotkey Registration Protocol

/// Abstracts global hotkey registration for testability.
protocol HotkeyRegistering {
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void)
    func unregister(keyCode: UInt16)
    func unregisterAll()
}
