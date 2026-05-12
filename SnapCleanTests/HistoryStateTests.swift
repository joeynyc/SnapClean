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
}

private final class MockHistoryManager: HistoryPersisting {
    let saveDirectory = URL(fileURLWithPath: "/tmp/SnapCleanTests", isDirectory: true)
    var savedHistoryCounts: [Int] = []
    var removedPaths: [String] = []

    func saveHistory(_ history: [ScreenshotItem]) {
        savedHistoryCounts.append(history.count)
    }

    func loadHistory() async -> [ScreenshotItem] {
        []
    }

    func removeFiles(atPaths paths: [String]) {
        removedPaths.append(contentsOf: paths)
    }

    func isPathAllowed(_ path: String) -> Bool {
        path.hasPrefix(saveDirectory.path)
    }
}
