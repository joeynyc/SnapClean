import XCTest
import AppKit
@testable import SnapClean

@MainActor
final class ThumbnailStorageTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeManager() -> ScreenshotHistoryManager {
        ScreenshotHistoryManager(
            saveDirectory: root.appendingPathComponent("Downloads"),
            storeDirectory: root.appendingPathComponent("Store")
        )
    }

    private func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 60, height: 40))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 60, height: 40).fill()
        image.unlockFocus()
        return image
    }

    func testLegacyInlineThumbnailsMigrateToFilesAndLeaveJSON() async throws {
        let manager = makeManager()
        let shot = root.appendingPathComponent("shot.png")
        try Data([1, 2, 3]).write(to: shot)
        let id = UUID()
        let thumb = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let legacy = """
        [{"id":"\(id.uuidString)","date":0,"filePath":"\(shot.path)","thumbnail":"\(thumb.base64EncodedString())"}]
        """
        try legacy.write(to: manager.storeDirectory.appendingPathComponent("history.json"), atomically: true, encoding: .utf8)

        let items = await manager.loadHistory()

        XCTAssertEqual(items.map(\.id), [id])
        XCTAssertNil(items[0].legacyThumbnail)
        XCTAssertEqual(try Data(contentsOf: manager.thumbnailURL(for: id)), thumb)
        let json = try String(contentsOf: manager.storeDirectory.appendingPathComponent("history.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("thumbnail"))
        XCTAssertTrue(json.contains(id.uuidString))
    }

    func testEncodedItemsNeverContainThumbnailData() throws {
        let item = ScreenshotItem(filePath: "/tmp/a.png")
        let json = String(decoding: try JSONEncoder().encode([item]), as: UTF8.self)
        XCTAssertFalse(json.contains("thumbnail"))
    }

    func testHistoryJSONWrittenOncePerCaptureAndThumbnailFileCreated() async throws {
        let manager = CountingManager(store: root)
        let state = HistoryState(historyManager: manager)

        state.addToHistory(path: "/tmp/one.png", image: image(), limit: 5)
        await state.waitForPendingThumbnails()

        XCTAssertEqual(manager.saveHistoryCount, 1)
        let id = state.screenshotHistory[0].id
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.thumbnailURL(for: id).path))
        XCTAssertEqual(state.thumbnailRevisions[id], 1)
    }

    func testDeleteTrimAndClearRemoveThumbnails() async throws {
        let manager = CountingManager(store: root)
        let state = HistoryState(historyManager: manager)

        state.addToHistory(path: "/tmp/one.png", image: image(), limit: 2)
        let trimmedID = state.screenshotHistory[0].id
        state.addToHistory(path: "/tmp/two.png", image: image(), limit: 2)
        state.addToHistory(path: "/tmp/three.png", image: image(), limit: 2)
        await state.waitForPendingThumbnails()
        XCTAssertTrue(manager.removedThumbnailIDs.contains(trimmedID))

        let deleted = state.screenshotHistory[0]
        state.deleteHistoryItem(deleted)
        XCTAssertTrue(manager.removedThumbnailIDs.contains(deleted.id))

        let remaining = state.screenshotHistory[0]
        state.clearHistory()
        XCTAssertTrue(manager.removedThumbnailIDs.contains(remaining.id))
    }
}

private final class CountingManager: HistoryPersisting {
    let saveDirectory = URL(fileURLWithPath: "/tmp/SnapCleanTests", isDirectory: true)
    let store: URL
    var saveHistoryCount = 0
    var requestedThumbnailIDs: [UUID] = []
    var removedThumbnailIDs: [UUID] = []

    init(store: URL) {
        self.store = store
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    }

    func saveHistory(_ history: [ScreenshotItem]) { saveHistoryCount += 1 }
    func loadHistory() async -> [ScreenshotItem] { [] }
    func removeFiles(atPaths paths: [String]) {}
    func trashFile(atPath path: String) {}
    func isPathAllowed(_ path: String) -> Bool { false }

    func thumbnailURL(for id: UUID) -> URL { store.appendingPathComponent("\(id.uuidString).jpg") }
    func saveThumbnail(_ data: Data, for id: UUID) async {
        requestedThumbnailIDs.append(id)
        try? data.write(to: thumbnailURL(for: id))
    }
    func removeThumbnails(for ids: [UUID]) { removedThumbnailIDs.append(contentsOf: ids) }
}
