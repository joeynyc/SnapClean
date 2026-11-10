import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import SnapClean

// MARK: - Setting

final class AfterCaptureActionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SnapCleanTests.AfterCapture.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToOpeningTheEditor() {
        XCTAssertEqual(AfterCaptureAction.load(from: defaults), .openEditor)
        XCTAssertEqual(AfterCaptureAction.defaultValue, .openEditor)
    }

    func testStoredChoiceRoundTrips() {
        AfterCaptureAction.floatingThumbnail.store(in: defaults)
        XCTAssertEqual(defaults.string(forKey: AfterCaptureAction.defaultsKey), "floatingThumbnail")
        XCTAssertEqual(AfterCaptureAction.load(from: defaults), .floatingThumbnail)

        AfterCaptureAction.openEditor.store(in: defaults)
        XCTAssertEqual(AfterCaptureAction.load(from: defaults), .openEditor)
    }

    func testUnknownStoredValueFallsBackToDefault() {
        defaults.set("somethingElse", forKey: AfterCaptureAction.defaultsKey)
        XCTAssertEqual(AfterCaptureAction.load(from: defaults), .openEditor)
    }

    func testOutcomeHonorsShowPreviewToggle() {
        XCTAssertEqual(AfterCaptureOutcome(showPreview: true, action: .openEditor), .openEditor)
        XCTAssertEqual(AfterCaptureOutcome(showPreview: true, action: .floatingThumbnail), .showFloatingThumbnail)
        XCTAssertEqual(AfterCaptureOutcome(showPreview: false, action: .openEditor), .saveImmediately)
        XCTAssertEqual(AfterCaptureOutcome(showPreview: false, action: .floatingThumbnail), .saveImmediately)
    }
}

// MARK: - Dismiss schedule

final class ThumbnailDismissScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testDueAfterDelay() {
        let schedule = ThumbnailDismissSchedule(delay: 6, startingAt: start)
        XCTAssertFalse(schedule.isDue(at: start.addingTimeInterval(5.9)))
        XCTAssertTrue(schedule.isDue(at: start.addingTimeInterval(6)))
    }

    func testHoverPausesAndLeavingRestartsTheFullDelay() {
        var schedule = ThumbnailDismissSchedule(delay: 6, startingAt: start)
        schedule.setHovered(true, at: start.addingTimeInterval(5))
        XCTAssertNil(schedule.deadline)
        XCTAssertFalse(schedule.isDue(at: start.addingTimeInterval(100)))

        schedule.setHovered(false, at: start.addingTimeInterval(100))
        XCTAssertFalse(schedule.isDue(at: start.addingTimeInterval(105)))
        XCTAssertTrue(schedule.isDue(at: start.addingTimeInterval(106)))
    }

    func testRepeatedUnhoverDoesNotPushTheDeadline() {
        var schedule = ThumbnailDismissSchedule(delay: 6, startingAt: start)
        schedule.setHovered(false, at: start.addingTimeInterval(3))
        XCTAssertEqual(schedule.deadline, start.addingTimeInterval(6))
    }

    func testHoldsNestAndSurviveHoverChanges() {
        var schedule = ThumbnailDismissSchedule(delay: 6, startingAt: start)
        schedule.beginHold(at: start)
        schedule.beginHold(at: start)
        schedule.setHovered(true, at: start)
        schedule.setHovered(false, at: start)
        XCTAssertTrue(schedule.isPaused)

        schedule.endHold(at: start)
        XCTAssertTrue(schedule.isPaused)
        schedule.endHold(at: start.addingTimeInterval(10))
        XCTAssertFalse(schedule.isPaused)
        XCTAssertEqual(schedule.deadline, start.addingTimeInterval(16))
    }

    func testUnbalancedEndHoldIsIgnored() {
        var schedule = ThumbnailDismissSchedule(delay: 6, startingAt: start)
        schedule.endHold(at: start.addingTimeInterval(4))
        XCTAssertEqual(schedule.holdCount, 0)
        XCTAssertEqual(schedule.deadline, start.addingTimeInterval(6))
    }

    func testOnlyCloseAndOpenInEditorSkipSaving() {
        let saving: [FloatingThumbnailEnding] = [.timedOut, .replaced, .appTerminating, .saved, .pinned]
        XCTAssertTrue(saving.allSatisfy(\.savesCapture))
        XCTAssertFalse(FloatingThumbnailEnding.closed.savesCapture)
        XCTAssertFalse(FloatingThumbnailEnding.openedInEditor.savesCapture)
    }
}

// MARK: - State

@MainActor
final class FloatingThumbnailStateTests: XCTestCase {
    private var clock = Date()
    private var mouseDown = false
    private var presenter: MockThumbnailPresenter!
    private var actions: MockThumbnailActions!
    private var shareRoot: URL!

    override func setUp() {
        super.setUp()
        clock = Date()
        mouseDown = false
        presenter = MockThumbnailPresenter()
        actions = MockThumbnailActions()
        shareRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapCleanThumbTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: shareRoot)
        super.tearDown()
    }

    private func makeState() -> FloatingThumbnailState {
        let state = FloatingThumbnailState(
            presenter: presenter,
            delay: 6,
            exporter: TemporaryShareFile(root: shareRoot),
            now: { [unowned self] in self.clock },
            isMouseButtonDown: { [unowned self] in self.mouseDown }
        )
        state.actions = actions
        return state
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    func testPresentShowsPanelNearPoint() {
        let state = makeState()
        let image = makeTestImage()
        state.present(image, near: CGPoint(x: 10, y: 20))

        XCTAssertTrue(state.isShowing)
        XCTAssertTrue(state.image === image)
        XCTAssertEqual(presenter.shownPoints, [CGPoint(x: 10, y: 20)])
        state.close()
    }

    func testTimeoutSavesOnceAndHides() {
        let state = makeState()
        let image = makeTestImage()
        state.present(image, near: nil)

        advance(5)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing)
        XCTAssertTrue(actions.saved.isEmpty)

        advance(1)
        state.checkDeadline()
        state.checkDeadline()
        XCTAssertFalse(state.isShowing)
        XCTAssertEqual(actions.saved.count, 1)
        XCTAssertTrue(actions.saved.first === image)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testHoverPreventsTimeout() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        advance(3)
        state.setHovered(true)
        advance(60)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing)

        state.setHovered(false)
        advance(5)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing, "leaving restarts the countdown")
        advance(1)
        state.checkDeadline()
        XCTAssertFalse(state.isShowing)
        XCTAssertEqual(actions.saved.count, 1)
    }

    func testCloseDiscardsWithoutSaving() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        state.close()

        XCTAssertFalse(state.isShowing)
        XCTAssertTrue(actions.saved.isEmpty)
        XCTAssertEqual(presenter.hideCount, 1)

        advance(10)
        state.checkDeadline()
        XCTAssertTrue(actions.saved.isEmpty)
    }

    func testClickOpensEditorWithoutSaving() {
        let state = makeState()
        let image = makeTestImage()
        state.present(image, near: nil)
        state.openEditor()

        XCTAssertFalse(state.isShowing)
        XCTAssertTrue(actions.saved.isEmpty)
        XCTAssertEqual(actions.editorImages.count, 1)
        XCTAssertTrue(actions.editorImages.first === image)
    }

    func testSaveButtonSavesAndDismisses() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        state.save()
        XCTAssertFalse(state.isShowing)
        XCTAssertEqual(actions.saved.count, 1)
    }

    func testPinSavesThenPinsWithSavedPath() {
        let state = makeState()
        let image = makeTestImage()
        state.present(image, near: nil)
        state.pin()

        XCTAssertEqual(actions.saved.count, 1)
        XCTAssertEqual(actions.pins.count, 1)
        XCTAssertTrue(actions.pins.first?.image === image)
        XCTAssertEqual(actions.pins.first?.path, "/tmp/thumb-1.png")
    }

    func testPinAfterFailedSavePinsUnsavedImage() {
        actions.saveSucceeds = false
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        state.pin()

        XCTAssertEqual(actions.pins.count, 1)
        XCTAssertNil(actions.pins.first?.path)
    }

    func testCopyKeepsThumbnail() {
        let state = makeState()
        let image = makeTestImage()
        state.present(image, near: nil)
        state.copy()

        XCTAssertTrue(state.isShowing)
        XCTAssertEqual(actions.copied.count, 1)
        XCTAssertTrue(actions.copied.first === image)
        state.close()
    }

    func testNewCaptureSavesAndReplacesTheOldOne() {
        let state = makeState()
        let first = makeTestImage()
        let second = makeTestImage()
        state.present(first, near: nil)
        advance(2)
        state.present(second, near: nil)

        XCTAssertEqual(actions.saved.count, 1)
        XCTAssertTrue(actions.saved.first === first)
        XCTAssertTrue(state.image === second)
        XCTAssertEqual(presenter.shownPoints.count, 2)

        // The replacement gets its own full countdown.
        advance(5)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing)
        advance(1)
        state.checkDeadline()
        XCTAssertEqual(actions.saved.count, 2)
        XCTAssertTrue(actions.saved.last === second)
    }

    func testAppTerminationSavesTheShowingCapture() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        state.finish(.appTerminating)
        XCTAssertEqual(actions.saved.count, 1)

        state.finish(.appTerminating)
        XCTAssertEqual(actions.saved.count, 1, "nothing left to save")
    }

    func testShareHoldPausesUntilPickerCloses() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        let hold = state.beginHold()
        advance(30)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing)

        state.endHold(hold)
        advance(6)
        state.checkDeadline()
        XCTAssertFalse(state.isShowing)
    }

    func testHoldFromAPreviousThumbnailCannotReleaseTheNextOne() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        let staleHold = state.beginHold()
        state.present(makeTestImage(), near: nil)
        let currentHold = state.beginHold()

        state.endHold(staleHold)
        advance(30)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing)

        state.endHold(currentHold)
        state.close()
    }

    func testShareExportWritesTemporaryPNG() throws {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        let url = try XCTUnwrap(state.exportForSharing())

        XCTAssertTrue(url.path.hasPrefix(shareRoot.path))
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(actions.saved.isEmpty, "sharing doesn't save to Downloads")
        state.close()
    }

    func testDragOutHoldsUntilMouseUp() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        mouseDown = true
        let provider = state.beginDragOut()
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))

        advance(30)
        state.pollDragEnd()
        state.checkDeadline()
        XCTAssertTrue(state.isShowing, "still dragging")

        mouseDown = false
        state.pollDragEnd()
        advance(5)
        state.checkDeadline()
        XCTAssertTrue(state.isShowing, "countdown restarts after the drop")
        advance(1)
        state.checkDeadline()
        XCTAssertFalse(state.isShowing)
        XCTAssertEqual(actions.saved.count, 1)
    }

    func testButtonsDoNothingOnceDismissed() {
        let state = makeState()
        state.present(makeTestImage(), near: nil)
        state.close()

        state.copy()
        state.save()
        state.pin()
        state.openEditor()
        XCTAssertNil(state.exportForSharing())
        XCTAssertTrue(actions.copied.isEmpty)
        XCTAssertTrue(actions.saved.isEmpty)
        XCTAssertTrue(actions.pins.isEmpty)
        XCTAssertTrue(actions.editorImages.isEmpty)
        XCTAssertEqual(presenter.hideCount, 1)
    }
}

// MARK: - AppState integration

@MainActor
final class FloatingThumbnailAppStateTests: XCTestCase {
    func testThumbnailSaveGoesThroughCaptureServiceAndHistory() {
        let capture = ShareMockCapture()
        let presenter = MockThumbnailPresenter()
        let state = AppState(screenCapture: capture, historyManager: ShareMockHistory(), thumbnailPresenter: presenter)

        state.showFloatingThumbnail(for: makeTestImage())
        XCTAssertTrue(state.floatingThumbnail.isShowing)
        XCTAssertEqual(presenter.shownPoints.count, 1)
        XCTAssertFalse(state.capture.showAnnotationCanvas, "the editor stays closed")
        XCTAssertEqual(capture.saveCount, 0)

        state.floatingThumbnail.finish(.timedOut)
        XCTAssertEqual(capture.saveCount, 1)
        XCTAssertEqual(state.history.screenshotHistory.map(\.filePath), ["/tmp/share-saved-1.png"])
    }

    func testThumbnailClickOpensEditorWithFreshAnnotations() {
        let presenter = MockThumbnailPresenter()
        let state = AppState(screenCapture: ShareMockCapture(), historyManager: ShareMockHistory(), thumbnailPresenter: presenter)
        state.annotations.addAnnotation(AnnotationElement(tool: .pencil, points: [.zero, CGPoint(x: 0.5, y: 0.5)], color: .red, lineWidth: 2))
        let image = makeTestImage()

        state.showFloatingThumbnail(for: image)
        XCTAssertEqual(state.annotations.elements.count, 1, "showing the thumbnail leaves the editor alone")

        state.floatingThumbnail.openEditor()
        XCTAssertTrue(state.capture.capturedImage === image)
        XCTAssertTrue(state.capture.showAnnotationCanvas)
        XCTAssertTrue(state.annotations.elements.isEmpty)
        XCTAssertTrue(state.history.screenshotHistory.isEmpty)
    }

    func testFailedThumbnailSaveReportsError() {
        let capture = ShareMockCapture()
        capture.saveSucceeds = false
        let state = AppState(screenCapture: capture, historyManager: ShareMockHistory(), thumbnailPresenter: MockThumbnailPresenter())

        state.showFloatingThumbnail(for: makeTestImage())
        state.floatingThumbnail.save()

        XCTAssertEqual(state.capture.lastCaptureError, .saveFailed("/tmp/SnapCleanTests"))
        XCTAssertTrue(state.history.screenshotHistory.isEmpty)
    }
}

// MARK: - Layout

final class FloatingThumbnailLayoutTests: XCTestCase {
    func testThumbnailFitsAndKeepsAspect() {
        XCTAssertEqual(FloatingThumbnailLayout.thumbnailSize(for: CGSize(width: 2400, height: 1200)), CGSize(width: 240, height: 120))
        XCTAssertEqual(FloatingThumbnailLayout.thumbnailSize(for: CGSize(width: 800, height: 1600)), CGSize(width: 180, height: 160))
    }

    func testTinyOrEmptyImagesGetTheMinimumCard() {
        XCTAssertEqual(FloatingThumbnailLayout.thumbnailSize(for: CGSize(width: 20, height: 10)), FloatingThumbnailLayout.minThumbnailSize)
        XCTAssertEqual(FloatingThumbnailLayout.thumbnailSize(for: .zero), FloatingThumbnailLayout.minThumbnailSize)
    }

    func testPanelSitsInBottomRightOfVisibleFrame() {
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 795)
        let card = CGSize(width: 240, height: 120)
        let panelSize = FloatingThumbnailLayout.panelSize(forThumbnail: card)
        let frame = FloatingThumbnailLayout.panelFrame(panelSize: panelSize, in: visible)
        let padding = FloatingThumbnailLayout.shadowPadding
        let margin = FloatingThumbnailLayout.screenMargin

        // The card (inside the shadow padding) is `screenMargin` from the right and bottom edges.
        XCTAssertEqual(frame.maxX - padding, visible.maxX - margin)
        XCTAssertEqual(frame.minY + padding, visible.minY + margin)
        XCTAssertEqual(frame.size, panelSize)
    }

    func testPicksTheScreenUnderThePointer() {
        let main = FloatingThumbnailLayout.ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        let right = FloatingThumbnailLayout.ScreenInfo(
            frame: CGRect(x: 1440, y: -200, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        )
        let screens = [main, right]

        XCTAssertEqual(
            FloatingThumbnailLayout.visibleFrame(containing: CGPoint(x: 2000, y: 100), screens: screens, fallback: main),
            right.visibleFrame
        )
        XCTAssertEqual(
            FloatingThumbnailLayout.visibleFrame(containing: CGPoint(x: 1440, y: 100), screens: screens, fallback: main),
            right.visibleFrame,
            "a shared edge belongs to the screen on the right"
        )
        XCTAssertEqual(
            FloatingThumbnailLayout.visibleFrame(containing: CGPoint(x: -500, y: 100), screens: screens, fallback: main),
            main.visibleFrame
        )
        XCTAssertEqual(
            FloatingThumbnailLayout.visibleFrame(containing: nil, screens: screens, fallback: nil),
            main.visibleFrame
        )
        XCTAssertNil(FloatingThumbnailLayout.visibleFrame(containing: nil, screens: [], fallback: nil))
    }
}

// MARK: - Mocks

@MainActor
final class MockThumbnailPresenter: FloatingThumbnailPresenting {
    var shownPoints: [CGPoint?] = []
    var hideCount = 0

    func show(_ state: FloatingThumbnailState, image: NSImage, near point: CGPoint?) {
        shownPoints.append(point)
    }

    func hide() {
        hideCount += 1
    }
}

@MainActor
final class MockThumbnailActions: FloatingThumbnailActions {
    var saveSucceeds = true
    var saved: [NSImage] = []
    var editorImages: [NSImage] = []
    var pins: [(image: NSImage, path: String?)] = []
    var copied: [NSImage] = []

    func saveThumbnailCapture(_ image: NSImage) -> String? {
        guard saveSucceeds else { return nil }
        saved.append(image)
        return "/tmp/thumb-\(saved.count).png"
    }

    func openEditor(with image: NSImage) { editorImages.append(image) }
    func pinToScreen(_ image: NSImage, sourcePath: String?) { pins.append((image, sourcePath)) }
    func copyImageToClipboard(_ image: NSImage) { copied.append(image) }
}
