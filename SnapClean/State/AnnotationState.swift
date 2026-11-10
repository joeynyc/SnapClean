import SwiftUI

// MARK: - AnnotationState

@Observable @MainActor
final class AnnotationState {
    @ObservationIgnored private let maxUndoRedoDepth = 30

    /// Text annotations use a font size of `lineWidth * textSizeMultiplier`.
    nonisolated static let textSizeMultiplier: CGFloat = 8

    var selectedTool: AnnotationTool = .arrow {
        didSet {
            if selectedTool != oldValue { commitTextDraft() }
        }
    }
    var selectedColor: Color = .red
    var lineWidth: CGFloat = 2.0
    var elements: [AnnotationElement] = []
    var undoStack: [[AnnotationElement]] = []
    var redoStack: [[AnnotationElement]] = []
    private(set) var canUndo: Bool = false
    private(set) var canRedo: Bool = false
    /// The text box currently being typed into, drawn with the live color and line width.
    var textDraft: TextDraft?

    /// Places a new text box at `point` (in `rect`'s coordinate space), committing any open one.
    func beginTextDraft(at point: CGPoint, in rect: CGRect) {
        commitTextDraft()
        guard rect.width > 0, rect.height > 0 else { return }
        textDraft = TextDraft(
            origin: AnnotationElement.normalize(point, in: rect),
            referenceDimension: max(min(rect.width, rect.height), 1)
        )
    }

    /// Turns the open text box into an annotation; a box with only whitespace is discarded.
    func commitTextDraft() {
        guard let draft = textDraft else { return }
        textDraft = nil
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        addAnnotation(AnnotationElement(
            tool: .text,
            points: [draft.origin],
            color: selectedColor,
            lineWidth: lineWidth / draft.referenceDimension,
            text: draft.text,
            fontSize: lineWidth * Self.textSizeMultiplier / draft.referenceDimension
        ))
    }

    func cancelTextDraft() {
        textDraft = nil
    }

    func addAnnotation(_ element: AnnotationElement) {
        undoStack.append(elements)
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        elements.append(element)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func undo() {
        commitTextDraft()
        guard let lastState = undoStack.popLast() else { return }
        redoStack.append(elements)
        if redoStack.count > maxUndoRedoDepth {
            redoStack.removeFirst()
        }
        elements = lastState
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func redo() {
        commitTextDraft()
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(elements)
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        elements = nextState
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func clearAnnotations() {
        commitTextDraft()
        undoStack.append(elements)
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        elements = []
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func resetAnnotationState() {
        textDraft = nil
        elements = []
        undoStack = []
        redoStack = []
        canUndo = false
        canRedo = false
    }
}
