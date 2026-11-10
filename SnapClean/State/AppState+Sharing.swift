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
