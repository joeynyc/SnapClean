import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import SnapClean

final class ShareExportTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapCleanShareTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 6))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 6).fill()
        image.unlockFocus()
        return image
    }

    func testFileNameMatchesSavedScreenshots() {
        // 2026-11-09 14:25:01 UTC
        let date = Date(timeIntervalSince1970: 1_794_234_301)
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(ScreenshotFileNaming.fileName(for: date, timeZone: utc), "SnapClean_2026-11-09_142501.png")
        XCTAssertEqual(ScreenshotFileNaming.baseName(for: date, timeZone: utc), "SnapClean_2026-11-09_142501")
    }

    func testWriteProducesReadablePNGWithScreenshotName() throws {
        let exporter = TemporaryShareFile(root: root)
        let date = Date()
        let url = try XCTUnwrap(exporter.write(makeImage(), date: date))

        XCTAssertEqual(url.lastPathComponent, ScreenshotFileNaming.fileName(for: date))
        XCTAssertTrue(url.path.hasPrefix(root.path))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47]) // PNG signature
        XCTAssertNotNil(NSImage(contentsOf: url))
    }

    func testExportsInTheSameSecondDoNotOverwriteEachOther() throws {
        let exporter = TemporaryShareFile(root: root)
        let date = Date()
        let first = try XCTUnwrap(exporter.write(makeImage(), date: date))
        let second = try XCTUnwrap(exporter.write(makeImage(), date: date))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testPruneRemovesOnlyExpiredExports() throws {
        let exporter = TemporaryShareFile(root: root, maxAge: 60)
        let url = try XCTUnwrap(exporter.write(makeImage()))

        exporter.prune(now: Date().addingTimeInterval(30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        exporter.prune(now: Date().addingTimeInterval(120))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    func testUnencodableImageIsNotWritten() {
        let exporter = TemporaryShareFile(root: root)
        XCTAssertNil(exporter.write(NSImage()))
    }

    func testDragProviderOffersFileURLAndPNG() throws {
        let exporter = TemporaryShareFile(root: root)
        let url = try XCTUnwrap(exporter.write(makeImage()))
        let provider = ScreenshotDragItem.provider(forFileAt: url)

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
        XCTAssertEqual(provider.suggestedName, url.deletingPathExtension().lastPathComponent)

        let loaded = expectation(description: "png data")
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            XCTAssertEqual(data, try? Data(contentsOf: url))
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
    }

    func testHistoryDragUsesTheSavedFile() throws {
        let saved = try XCTUnwrap(TemporaryShareFile(root: root).write(makeImage()))
        let provider = ScreenshotDragItem.provider(forSavedFileAtPath: saved.path)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))

        let loaded = expectation(description: "file url")
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            XCTAssertEqual((object as? URL)?.standardizedFileURL, saved.standardizedFileURL)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
    }

    func testHistoryDragOfDeletedFileIsEmpty() {
        let provider = ScreenshotDragItem.provider(forSavedFileAtPath: root.appendingPathComponent("gone.png").path)
        XCTAssertTrue(provider.registeredTypeIdentifiers.isEmpty)
    }

    func testDragProviderForMissingImageIsEmpty() {
        let provider = ScreenshotDragItem.provider(for: nil, exporter: TemporaryShareFile(root: root))
        XCTAssertTrue(provider.registeredTypeIdentifiers.isEmpty)
    }
}
