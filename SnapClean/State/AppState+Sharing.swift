import AppKit

// MARK: - Share and drag out

extension AppState {
    /// Writes the editor's annotated image (open text box included) to a temporary PNG for the
    /// share picker or a drag. Nothing is added to History.
    func exportEditorImageForSharing() -> URL? {
        guard let image = currentEditableImage() else { return nil }
        return TemporaryShareFile().write(image)
    }

    /// The pinned image as a file: its saved file when it has one, otherwise a temporary PNG.
    func exportPinnedImageForSharing() -> URL? {
        if let path = pinnedSourcePath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        guard let image = pinnedImage else { return nil }
        return TemporaryShareFile().write(image)
    }
}

// MARK: - Floating thumbnail

extension AppState: FloatingThumbnailActions {
    /// The floating-thumbnail branch of `handleCapturedImage`: ends the capture without opening
    /// the editor (whatever it holds is left alone) and shows the thumbnail instead.
    func showFloatingThumbnail(for image: NSImage) {
        // Tears down the overlay and timer and restores the main window only if it was open,
        // exactly what a finished capture needs when it skips the editor.
        cancelCapture()
        if copyAfterCapture {
            capture.screenCapture.copyToClipboard(image)
        }
        // The pointer is on the screen the capture came from (the region or window was just clicked).
        floatingThumbnail.present(image, near: NSEvent.mouseLocation)
    }

    func saveThumbnailCapture(_ image: NSImage) -> String? {
        let directory = history.historyManager.saveDirectory
        guard let path = capture.screenCapture.saveImage(image, to: directory) else {
            capture.lastCaptureError = .saveFailed(directory.path)
            capture.revealMainWindow()
            appLogger.error("Failed to save floating thumbnail capture to \(directory.path, privacy: .public)")
            return nil
        }
        addToHistory(path: path, image: image)
        return path
    }

    /// Opens the editor on `image`, as a capture in "Open editor" mode does.
    func openEditor(with image: NSImage) {
        capture.capturedImage = image
        annotations.resetAnnotationState()
        capture.showAnnotationCanvas = true
        capture.revealMainWindow()
    }

    func copyImageToClipboard(_ image: NSImage) {
        capture.screenCapture.copyToClipboard(image)
    }
}
