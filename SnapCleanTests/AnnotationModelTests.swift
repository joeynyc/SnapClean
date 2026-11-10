import XCTest
import SwiftUI
import AppKit
@testable import SnapClean

final class AnnotationModelTests: XCTestCase {
    func testAnnotationNormalizationRoundTripsThroughDisplayRect() throws {
        let rect = CGRect(x: 20, y: 10, width: 200, height: 100)

        let normalized = try XCTUnwrap(AnnotationElement.normalized(
            tool: .rectangle,
            color: .red,
            lineWidth: 4,
            startPoint: CGPoint(x: 70, y: 35),
            endPoint: CGPoint(x: 170, y: 85),
            in: rect
        ))

        XCTAssertEqual(normalized.startPoint?.x ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(normalized.startPoint?.y ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(normalized.endPoint?.x ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(normalized.endPoint?.y ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(normalized.lineWidth, 0.04, accuracy: 0.0001)

        let denormalized = normalized.denormalized(in: rect)
        XCTAssertEqual(denormalized.startPoint?.x ?? -1, 70, accuracy: 0.0001)
        XCTAssertEqual(denormalized.startPoint?.y ?? -1, 35, accuracy: 0.0001)
        XCTAssertEqual(denormalized.endPoint?.x ?? -1, 170, accuracy: 0.0001)
        XCTAssertEqual(denormalized.endPoint?.y ?? -1, 85, accuracy: 0.0001)
        XCTAssertEqual(denormalized.lineWidth, 4, accuracy: 0.0001)
    }

    func testEffectAnnotationProvidesRectAndAmount() {
        let blur = AnnotationElement(
            tool: .blur,
            lineWidth: 3,
            startPoint: CGPoint(x: 90, y: 40),
            endPoint: CGPoint(x: 10, y: 80)
        )

        XCTAssertEqual(blur.effectRect, CGRect(x: 10, y: 40, width: 80, height: 40))
        XCTAssertEqual(blur.effectAmount, 6, accuracy: 0.0001)

        let pixelate = AnnotationElement(
            tool: .pixelate,
            lineWidth: 5,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 40, y: 30)
        )

        XCTAssertEqual(pixelate.effectRect, CGRect(x: 0, y: 0, width: 40, height: 30))
        XCTAssertEqual(pixelate.effectAmount, 20, accuracy: 0.0001)
    }
}

// MARK: - Annotation state (undo/redo, text drafts)

@MainActor
final class AnnotationStateTests: XCTestCase {
    private func arrow() -> AnnotationElement {
        AnnotationElement(tool: .arrow, startPoint: .zero, endPoint: CGPoint(x: 0.5, y: 0.5))
    }

    func testUndoAndRedoStepThroughAddedAnnotations() {
        let state = AnnotationState()
        let first = arrow()
        let second = arrow()
        state.addAnnotation(first)
        state.addAnnotation(second)

        state.undo()
        XCTAssertEqual(state.elements, [first])
        XCTAssertTrue(state.canUndo)
        XCTAssertTrue(state.canRedo)

        state.undo()
        XCTAssertTrue(state.elements.isEmpty)
        XCTAssertFalse(state.canUndo)

        state.redo()
        state.redo()
        XCTAssertEqual(state.elements, [first, second])
        XCTAssertFalse(state.canRedo)
    }

    func testAddingAnnotationClearsRedo() {
        let state = AnnotationState()
        state.addAnnotation(arrow())
        state.undo()
        XCTAssertTrue(state.canRedo)

        state.addAnnotation(arrow())
        XCTAssertFalse(state.canRedo)
        XCTAssertTrue(state.redoStack.isEmpty)
    }

    func testUndoHistoryIsCapped() {
        let state = AnnotationState()
        for _ in 0..<40 { state.addAnnotation(arrow()) }
        var undos = 0
        while state.canUndo {
            state.undo()
            undos += 1
        }
        XCTAssertEqual(undos, 30)
        XCTAssertEqual(state.elements.count, 10)
    }

    func testClearAnnotationsCanBeUndone() {
        let state = AnnotationState()
        let element = arrow()
        state.addAnnotation(element)
        state.clearAnnotations()
        XCTAssertTrue(state.elements.isEmpty)

        state.undo()
        XCTAssertEqual(state.elements, [element])
    }

    func testResetClearsElementsHistoryAndDraft() {
        let state = AnnotationState()
        state.addAnnotation(arrow())
        state.addAnnotation(arrow())
        state.undo()
        state.beginTextDraft(at: CGPoint(x: 10, y: 10), in: CGRect(x: 0, y: 0, width: 100, height: 100))

        state.resetAnnotationState()

        XCTAssertTrue(state.elements.isEmpty)
        XCTAssertTrue(state.undoStack.isEmpty)
        XCTAssertTrue(state.redoStack.isEmpty)
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
        XCTAssertNil(state.textDraft)
    }

    func testCommittedTextIsNormalizedLikeTheEditorShowedIt() throws {
        let state = AnnotationState()
        state.lineWidth = 3
        state.selectedColor = .blue
        let displayRect = CGRect(x: 100, y: 50, width: 400, height: 200)
        state.beginTextDraft(at: CGPoint(x: 150, y: 100), in: displayRect)
        state.textDraft?.text = "Hello"

        state.commitTextDraft()

        XCTAssertNil(state.textDraft)
        let element = try XCTUnwrap(state.elements.first)
        XCTAssertEqual(element.tool, .text)
        XCTAssertEqual(element.text, "Hello")
        XCTAssertEqual(element.color, .blue)

        // On screen it was 3 * 8 = 24pt with its top-left corner at (150, 100)...
        let onScreen = element.denormalized(in: displayRect)
        XCTAssertEqual(onScreen.points.first?.x ?? -1, 150, accuracy: 0.0001)
        XCTAssertEqual(onScreen.points.first?.y ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(onScreen.fontSize ?? -1, 24, accuracy: 0.0001)

        // ...and the export of a 2x image keeps the same proportions.
        let exported = element.denormalized(in: CGRect(x: 0, y: 0, width: 800, height: 400))
        XCTAssertEqual(exported.points.first?.x ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(exported.points.first?.y ?? -1, 100, accuracy: 0.0001)
        XCTAssertEqual(exported.fontSize ?? -1, 48, accuracy: 0.0001)
    }

    func testBlankTextDraftIsDiscarded() {
        let state = AnnotationState()
        state.beginTextDraft(at: CGPoint(x: 5, y: 5), in: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.textDraft?.text = "  \n "

        state.commitTextDraft()

        XCTAssertNil(state.textDraft)
        XCTAssertTrue(state.elements.isEmpty)
        XCTAssertFalse(state.canUndo)
    }

    func testCancelDiscardsTextDraft() {
        let state = AnnotationState()
        state.beginTextDraft(at: CGPoint(x: 5, y: 5), in: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.textDraft?.text = "Draft"

        state.cancelTextDraft()

        XCTAssertNil(state.textDraft)
        XCTAssertTrue(state.elements.isEmpty)
    }

    func testSwitchingToolsCommitsTextDraft() {
        let state = AnnotationState()
        state.selectedTool = .text
        state.beginTextDraft(at: CGPoint(x: 5, y: 5), in: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.textDraft?.text = "Note"

        state.selectedTool = .arrow

        XCTAssertNil(state.textDraft)
        XCTAssertEqual(state.elements.map(\.text), ["Note"])
    }

    func testPlacingANewTextBoxCommitsTheOpenOne() {
        let state = AnnotationState()
        let rect = CGRect(x: 0, y: 0, width: 50, height: 50)
        state.beginTextDraft(at: CGPoint(x: 5, y: 5), in: rect)
        state.textDraft?.text = "First"

        state.beginTextDraft(at: CGPoint(x: 20, y: 20), in: rect)

        XCTAssertEqual(state.elements.map(\.text), ["First"])
        XCTAssertEqual(state.textDraft?.text, "")
    }

    func testUndoCommitsTextDraftAndUndoesIt() {
        let state = AnnotationState()
        state.beginTextDraft(at: CGPoint(x: 5, y: 5), in: CGRect(x: 0, y: 0, width: 50, height: 50))
        state.textDraft?.text = "Oops"

        state.undo()
        XCTAssertNil(state.textDraft)
        XCTAssertTrue(state.elements.isEmpty)

        state.redo()
        XCTAssertEqual(state.elements.map(\.text), ["Oops"])
    }
}

// MARK: - Arrow geometry

@MainActor
final class ArrowGeometryTests: XCTestCase {
    func testHeadLengthScalesWithLineWidth() throws {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 200, y: 0)
        let thin = try XCTUnwrap(AnnotationRenderer.arrowGeometry(start: start, end: end, lineWidth: 2))
        let thick = try XCTUnwrap(AnnotationRenderer.arrowGeometry(start: start, end: end, lineWidth: 4))

        let k = AnnotationRenderer.arrowHeadLengthPerLineWidth
        let cos30 = cos(CGFloat.pi / 6)
        XCTAssertEqual(thin.tip, end)
        XCTAssertEqual(end.x - thin.left.x, 2 * k * cos30, accuracy: 0.0001)
        XCTAssertEqual(end.x - thick.left.x, 4 * k * cos30, accuracy: 0.0001)
        XCTAssertEqual(thick.left.y, -thick.right.y, accuracy: 0.0001)
    }

    /// The editor draws at display size and the export at image size, with points and line
    /// width scaled by the same factor; the whole arrow must scale with them.
    func testGeometryScalesUniformlyBetweenEditorAndExport() throws {
        let start = CGPoint(x: 12, y: 30)
        let end = CGPoint(x: 90, y: 75)
        let scale: CGFloat = 3.5
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }

        let editor = try XCTUnwrap(AnnotationRenderer.arrowGeometry(start: start, end: end, lineWidth: 2))
        let export = try XCTUnwrap(AnnotationRenderer.arrowGeometry(
            start: scaled(start), end: scaled(end), lineWidth: 2 * scale
        ))

        for (a, b) in [(editor.left, export.left), (editor.right, export.right),
                       (editor.tip, export.tip), (editor.shaftEnd, export.shaftEnd)] {
            XCTAssertEqual(scaled(a).x, b.x, accuracy: 0.0001)
            XCTAssertEqual(scaled(a).y, b.y, accuracy: 0.0001)
        }
    }

    func testShaftStopsInsideTheHead() throws {
        let arrow = try XCTUnwrap(AnnotationRenderer.arrowGeometry(
            start: .zero, end: CGPoint(x: 100, y: 0), lineWidth: 5
        ))
        let headBase = arrow.left.x
        XCTAssertGreaterThan(arrow.shaftEnd.x, headBase)
        XCTAssertLessThan(arrow.shaftEnd.x, arrow.tip.x)
    }

    func testShortArrowHeadIsClampedToArrowLength() throws {
        let arrow = try XCTUnwrap(AnnotationRenderer.arrowGeometry(
            start: .zero, end: CGPoint(x: 10, y: 0), lineWidth: 10
        ))
        XCTAssertEqual(hypot(arrow.left.x - arrow.tip.x, arrow.left.y - arrow.tip.y), 10, accuracy: 0.0001)
    }

    func testZeroLengthArrowHasNoGeometry() {
        XCTAssertNil(AnnotationRenderer.arrowGeometry(
            start: CGPoint(x: 4, y: 4), end: CGPoint(x: 4, y: 4), lineWidth: 2
        ))
    }
}

// MARK: - AppState editor flow

@MainActor
final class AppStateEditorTests: XCTestCase {
    private var capture: MockScreenCapture!
    private var appState: AppState!

    override func setUp() async throws {
        capture = MockScreenCapture()
        appState = AppState(screenCapture: capture, historyManager: StubHistoryManager())
    }

    override func tearDown() async throws {
        appState = nil
        capture = nil
    }

    private func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 30))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        image.unlockFocus()
        return image
    }

    func testNewCaptureStartsWithNoAnnotations() {
        appState.handleCapturedImage(image())
        appState.annotations.addAnnotation(AnnotationElement(
            tool: .arrow, startPoint: .zero, endPoint: CGPoint(x: 1, y: 1)
        ))
        appState.annotations.beginTextDraft(at: CGPoint(x: 5, y: 5), in: CGRect(x: 0, y: 0, width: 40, height: 30))

        let next = image()
        appState.handleCapturedImage(next)

        XCTAssertTrue(appState.capture.capturedImage === next)
        XCTAssertTrue(appState.annotations.elements.isEmpty)
        XCTAssertFalse(appState.annotations.canUndo)
        XCTAssertNil(appState.annotations.textDraft)
    }

    func testEditableImageIncludesTextStillBeingTyped() {
        appState.capture.capturedImage = image()
        appState.annotations.beginTextDraft(at: CGPoint(x: 5, y: 5), in: CGRect(x: 0, y: 0, width: 40, height: 30))
        appState.annotations.textDraft?.text = "Typing"

        XCTAssertNotNil(appState.currentEditableImage())

        XCTAssertNil(appState.annotations.textDraft)
        XCTAssertEqual(appState.annotations.elements.map(\.text), ["Typing"])
    }

    func testFailedSaveFromEditorIsReportedAndKeepsWork() {
        capture.saveResult = nil
        appState.capture.capturedImage = image()
        appState.capture.showAnnotationCanvas = true
        appState.annotations.addAnnotation(AnnotationElement(
            tool: .arrow, startPoint: .zero, endPoint: CGPoint(x: 1, y: 1)
        ))

        appState.saveAnnotation()

        XCTAssertEqual(
            appState.capture.lastCaptureError,
            .saveFailed(appState.history.historyManager.saveDirectory.path)
        )
        XCTAssertTrue(appState.capture.showAnnotationCanvas)
        XCTAssertEqual(appState.annotations.elements.count, 1)
    }

    func testSuccessfulSaveClosesEditor() {
        appState.capture.capturedImage = image()
        appState.capture.showAnnotationCanvas = true

        appState.saveAnnotation()

        XCTAssertNil(appState.capture.lastCaptureError)
        XCTAssertFalse(appState.capture.showAnnotationCanvas)
        XCTAssertEqual(capture.savedImageCount, 1)
    }

    func testFailedCaptureRecordsError() {
        appState.endCaptureRestoringWindow(failure: .captureFailed(.window))

        XCTAssertEqual(appState.capture.lastCaptureError, .captureFailed(.window))
        XCTAssertFalse(appState.capture.isCapturing)
    }

    func testEndingCaptureWithoutFailureRecordsNoError() {
        appState.endCaptureRestoringWindow()

        XCTAssertNil(appState.capture.lastCaptureError)
    }
}

private final class MockScreenCapture: ScreenCapturing {
    var saveResult: String? = "/tmp/SnapCleanTests/shot.png"
    var savedImageCount = 0

    func captureRegion(rect: CGRect) async -> NSImage? { nil }
    func captureFullScreen() async -> NSImage? { nil }
    func captureWindowByID(_ windowID: CGWindowID) async -> NSImage? { nil }
    func getWindowList() async -> [(id: CGWindowID, name: String, bounds: CGRect)] { [] }
    func saveImage(_ image: NSImage, to folder: URL?) -> String? {
        savedImageCount += 1
        return saveResult
    }
    func copyToClipboard(_ image: NSImage) {}
    func openInFinder(_ path: String) {}
}

private final class StubHistoryManager: HistoryPersisting {
    let saveDirectory = URL(fileURLWithPath: "/tmp/SnapCleanTests", isDirectory: true)
    func saveHistory(_ history: [ScreenshotItem]) {}
    func loadHistory() async -> [ScreenshotItem] { [] }
    func removeFiles(atPaths paths: [String]) {}
    func trashFile(atPath path: String) {}
    func isPathAllowed(_ path: String) -> Bool { false }
}
