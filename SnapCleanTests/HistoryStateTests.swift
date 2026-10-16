import XCTest
import AppKit
@testable import SnapClean

@MainActor
final class HistoryStateTests: XCTestCase {
    func testAddToHistoryTrimsOverflowAndRemovesOldFiles() {
        let manager = MockHistoryManager()
        let state = HistoryState(historyManager: manager)
        let image = NSImage(size: NSSize(width: 12, height: 12))

        state.addToHistory(path: "/tmp/one.png", image: image, limit: 2)
        state.addToHistory(path: "/tmp/two.png", image: image, limit: 2)
        state.addToHistory(path: "/tmp/three.png", image: image, limit: 2)

        XCTAssertEqual(state.screenshotHistory.map(\.filePath), ["/tmp/three.png", "/tmp/two.png"])
        XCTAssertEqual(manager.removedPaths, ["/tmp/one.png"])
        XCTAssertEqual(manager.savedHistoryCounts.prefix(3), [1, 2, 2])
    }

    func testDeleteHistoryItemMovesFileToTrash() {
        let manager = MockHistoryManager()
        let state = HistoryState(historyManager: manager)
        let image = NSImage(size: NSSize(width: 12, height: 12))

        state.addToHistory(path: "/tmp/one.png", image: image, limit: 5)
        state.deleteHistoryItem(state.screenshotHistory[0])

        XCTAssertTrue(state.screenshotHistory.isEmpty)
        XCTAssertEqual(manager.trashedPaths, ["/tmp/one.png"])
        XCTAssertTrue(manager.removedPaths.isEmpty)
    }

    func testOnlyFilesInStoreDirectoryMayBeDeletedAutomatically() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = ScreenshotHistoryManager(
            saveDirectory: root.appendingPathComponent("Downloads"),
            storeDirectory: root.appendingPathComponent("Store")
        )

        XCTAssertTrue(manager.isPathAllowed(root.appendingPathComponent("Store/old.png").path))
        XCTAssertFalse(manager.isPathAllowed(root.appendingPathComponent("Downloads/new.png").path))
        XCTAssertFalse(manager.isPathAllowed(root.appendingPathComponent("Store2/other.png").path))
    }
}

private final class MockHistoryManager: HistoryPersisting {
    let saveDirectory = URL(fileURLWithPath: "/tmp/SnapCleanTests", isDirectory: true)
    var savedHistoryCounts: [Int] = []
    var removedPaths: [String] = []
    var trashedPaths: [String] = []

    func saveHistory(_ history: [ScreenshotItem]) {
        savedHistoryCounts.append(history.count)
    }

    func loadHistory() async -> [ScreenshotItem] {
        []
    }

    func removeFiles(atPaths paths: [String]) {
        removedPaths.append(contentsOf: paths)
    }

    func trashFile(atPath path: String) {
        trashedPaths.append(path)
    }

    func isPathAllowed(_ path: String) -> Bool {
        path.hasPrefix(saveDirectory.path)
    }
}
