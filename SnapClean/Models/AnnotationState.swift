import SwiftUI

// Note: AnnotationElement and AnnotationTool are defined in Screenshot.swift
// This file should be imported after Screenshot.swift or in the same compilation unit

@MainActor
class AnnotationState: ObservableObject {
    // Maximum undo/redo stack depth to prevent unbounded memory growth
    private let maxUndoRedoDepth = 30

    @Published var annotations: [AnnotationElement] = []
    @Published var undoStack: [[AnnotationElement]] = []
    @Published var redoStack: [[AnnotationElement]] = []
    @Published var selectedTool: AnnotationTool = .arrow
    @Published var selectedColor: Color = .red
    @Published var lineWidth: CGFloat = 2.0

    func addAnnotation(_ element: AnnotationElement) {
        undoStack.append(annotations)
        // Cap undo stack to prevent unbounded memory growth
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        annotations.append(element)
    }

    func undo() {
        guard let lastState = undoStack.popLast() else { return }
        redoStack.append(annotations)
        // Cap redo stack to prevent unbounded memory growth
        if redoStack.count > maxUndoRedoDepth {
            redoStack.removeFirst()
        }
        annotations = lastState
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(annotations)
        // Cap undo stack to prevent unbounded memory growth
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        annotations = nextState
    }

    func clearAnnotations() {
        undoStack.append(annotations)
        // Cap undo stack to prevent unbounded memory growth
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        annotations = []
    }

    func resetAnnotationState() {
        annotations = []
        undoStack = []
        redoStack = []
    }
}
