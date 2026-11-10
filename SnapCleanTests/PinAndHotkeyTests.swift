import XCTest
import AppKit
@testable import SnapClean

@MainActor
final class PinStateTests: XCTestCase {
    private func makeState() -> (AppState, PinMockCapture) {
        let capture = PinMockCapture()
        return (AppState(screenCapture: capture, historyManager: PinMockHistory()), capture)
    }

    private let image = NSImage(size: NSSize(width: 10, height: 10))

    func testSavingEditorPinTwiceWritesAndRecordsOnce() {
        let (state, capture) = makeState()
        state.pinToScreen(image)
        XCTAssertNil(state.pinnedSourcePath)

        state.savePinnedImage()
        state.savePinnedImage()

        XCTAssertEqual(capture.saveCount, 1)
        XCTAssertEqual(state.history.screenshotHistory.count, 1)
        XCTAssertEqual(state.pinnedSourcePath, "/tmp/saved-1.png")
        state.closePinnedImage()
    }

    func testHistoryPinNeverSavesAndRevealsOriginal() {
        let (state, capture) = makeState()
        state.pinToScreen(image, sourcePath: "/tmp/existing.png")

        state.savePinnedImage()
        state.revealPinnedImage()

        XCTAssertEqual(capture.saveCount, 0)
        XCTAssertTrue(state.history.screenshotHistory.isEmpty)
        XCTAssertEqual(capture.revealed, ["/tmp/existing.png"])
        state.closePinnedImage()
    }

    func testRevealOfEditorPinSavesOnceThenReveals() {
        let (state, capture) = makeState()
        state.pinToScreen(image)
        state.revealPinnedImage()
        state.revealPinnedImage()

        XCTAssertEqual(capture.saveCount, 1)
        XCTAssertEqual(capture.revealed, ["/tmp/saved-1.png", "/tmp/saved-1.png"])
        state.closePinnedImage()
    }

    func testCloseClearsSourcePath() {
        let (state, _) = makeState()
        state.pinToScreen(image, sourcePath: "/tmp/existing.png")
        state.closePinnedImage()
        XCTAssertNil(state.pinnedImage)
        XCTAssertNil(state.pinnedSourcePath)
    }
}

final class HotkeyManagerTests: XCTestCase {
    func testReRegisteringSameSignatureDoesNotDeadlock() {
        let manager = HotkeyManager.shared
        manager.unregisterAll()
        defer { manager.unregisterAll() }
        let mods: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        manager.register(keyCode: 80, modifiers: mods) {}   // F19
        manager.register(keyCode: 80, modifiers: mods) {}
        manager.unregister(keyCode: 80)
    }
}

private final class PinMockCapture: ScreenCapturing {
    var saveCount = 0
    var revealed: [String] = []
    func captureRegion(rect: CGRect) async -> NSImage? { nil }
    func captureFullScreen() async -> NSImage? { nil }
    func captureWindowByID(_ windowID: CGWindowID) async -> NSImage? { nil }
    func getWindowList() async -> [(id: CGWindowID, name: String, bounds: CGRect)] { [] }
    func saveImage(_ image: NSImage, to folder: URL?) -> String? {
        saveCount += 1
        return "/tmp/saved-\(saveCount).png"
    }
    func copyToClipboard(_ image: NSImage) {}
    func openInFinder(_ path: String) { revealed.append(path) }
}

private final class PinMockHistory: HistoryPersisting {
    let saveDirectory = URL(fileURLWithPath: "/tmp/SnapCleanTests", isDirectory: true)
    func saveHistory(_ history: [ScreenshotItem]) {}
    func loadHistory() async -> [ScreenshotItem] { [] }
    func removeFiles(atPaths paths: [String]) {}
    func trashFile(atPath path: String) {}
    func isPathAllowed(_ path: String) -> Bool { false }
}
