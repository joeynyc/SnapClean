import SwiftUI

// MARK: - HistoryState

@Observable @MainActor
final class HistoryState {
    var screenshotHistory: [ScreenshotItem] = []
    let historyManager: HistoryPersisting

    init(historyManager: HistoryPersisting = ScreenshotHistoryManager()) {
        self.historyManager = historyManager
    }

    func addToHistory(path: String, image: NSImage, limit: Int) {
        let itemID = UUID()
        let capturedAt = Date()

        let item = ScreenshotItem(id: itemID, date: capturedAt, filePath: path, thumbnail: nil)
        screenshotHistory.insert(item, at: 0)
        let removed = trimHistoryToLimit(limit: limit)
        historyManager.saveHistory(screenshotHistory)
        if !removed.isEmpty {
            historyManager.removeFiles(atPaths: removed.map(\.filePath))
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let thumbnail = image.jpegThumbnailData(maxSize: NSSize(width: 300, height: 200))
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let index = self.screenshotHistory.firstIndex(where: { $0.id == itemID }) else {
                    return
                }
                self.screenshotHistory[index] = ScreenshotItem(
                    id: itemID,
                    date: capturedAt,
                    filePath: path,
                    thumbnail: thumbnail
                )
                self.historyManager.saveHistory(self.screenshotHistory)
            }
        }
    }

    func loadHistory(limit: Int) async {
        screenshotHistory = await historyManager.loadHistory()
        let removed = trimHistoryToLimit(limit: limit)
        historyManager.saveHistory(screenshotHistory)
        if !removed.isEmpty {
            historyManager.removeFiles(atPaths: removed.map(\.filePath))
        }
    }

    func clearHistory() {
        let removed = screenshotHistory
        screenshotHistory.removeAll()
        historyManager.saveHistory([])
        historyManager.removeFiles(atPaths: removed.map(\.filePath))
    }

    func deleteHistoryItem(_ item: ScreenshotItem) {
        screenshotHistory.removeAll { $0.id == item.id }
        historyManager.saveHistory(screenshotHistory)
        historyManager.trashFile(atPath: item.filePath)
    }

    private func trimHistoryToLimit(limit: Int) -> [ScreenshotItem] {
        guard screenshotHistory.count > limit else { return [] }
        let overflow = Array(screenshotHistory.suffix(from: limit))
        screenshotHistory.removeLast(overflow.count)
        return overflow
    }
}
