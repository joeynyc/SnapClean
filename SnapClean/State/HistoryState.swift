import SwiftUI

// MARK: - HistoryState

@Observable @MainActor
final class HistoryState {
    var screenshotHistory: [ScreenshotItem] = []
    let historyManager: HistoryPersisting
    /// Bumped when an item's thumbnail file is written, so views reload it.
    private(set) var thumbnailRevisions: [UUID: Int] = [:]
    @ObservationIgnored private var thumbnailTasks: [UUID: Task<Void, Never>] = [:]

    init(historyManager: HistoryPersisting = ScreenshotHistoryManager()) {
        self.historyManager = historyManager
    }

    func addToHistory(path: String, image: NSImage, limit: Int) {
        let itemID = UUID()
        let item = ScreenshotItem(id: itemID, date: Date(), filePath: path)
        screenshotHistory.insert(item, at: 0)
        let removed = trimHistoryToLimit(limit: limit)
        // history.json holds metadata only, so it is written once per capture.
        historyManager.saveHistory(screenshotHistory)
        if !removed.isEmpty {
            historyManager.removeFiles(atPaths: removed.map(\.filePath))
            historyManager.removeThumbnails(for: removed.map(\.id))
        }

        let source = SendableImage(image: image)
        thumbnailTasks[itemID] = Task { @MainActor [weak self] in
            let data = await Task.detached(priority: .utility) {
                source.image.jpegThumbnailData(maxSize: NSSize(width: 300, height: 200))
            }.value
            guard let self else { return }
            self.thumbnailTasks[itemID] = nil
            guard let data, self.screenshotHistory.contains(where: { $0.id == itemID }) else { return }
            await self.historyManager.saveThumbnail(data, for: itemID)
            // The item may have been trimmed or deleted while the file was being written.
            if self.screenshotHistory.contains(where: { $0.id == itemID }) {
                self.thumbnailRevisions[itemID, default: 0] += 1
            } else {
                self.historyManager.removeThumbnails(for: [itemID])
            }
        }
    }

    /// Waits for in-flight thumbnail generation (used by tests).
    func waitForPendingThumbnails() async {
        for task in Array(thumbnailTasks.values) { await task.value }
    }

    func loadHistory(limit: Int) async {
        screenshotHistory = await historyManager.loadHistory()
        let removed = trimHistoryToLimit(limit: limit)
        historyManager.saveHistory(screenshotHistory)
        if !removed.isEmpty {
            historyManager.removeFiles(atPaths: removed.map(\.filePath))
            historyManager.removeThumbnails(for: removed.map(\.id))
        }
    }

    func clearHistory() {
        let removed = screenshotHistory
        screenshotHistory.removeAll()
        historyManager.saveHistory([])
        historyManager.removeFiles(atPaths: removed.map(\.filePath))
        historyManager.removeThumbnails(for: removed.map(\.id))
    }

    func deleteHistoryItem(_ item: ScreenshotItem) {
        screenshotHistory.removeAll { $0.id == item.id }
        historyManager.saveHistory(screenshotHistory)
        historyManager.trashFile(atPath: item.filePath)
        historyManager.removeThumbnails(for: [item.id])
    }

    private func trimHistoryToLimit(limit: Int) -> [ScreenshotItem] {
        guard screenshotHistory.count > limit else { return [] }
        let overflow = Array(screenshotHistory.suffix(from: limit))
        screenshotHistory.removeLast(overflow.count)
        return overflow
    }
}

/// Hands an NSImage to a background task; the image is only read there.
private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}
