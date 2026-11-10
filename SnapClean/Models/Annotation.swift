import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow = "Arrow"
    case text = "Text"
    case rectangle = "Rectangle"
    case oval = "Oval"
    case line = "Line"
    case pencil = "Pencil"
    case blur = "Blur"
    case pixelate = "Pixelate"

    var id: String { rawValue }

    // Tools currently implemented in the canvas interaction/rendering pipeline.
    static var selectableTools: [AnnotationTool] {
        [.arrow, .text, .rectangle, .oval, .line, .pencil, .blur, .pixelate]
    }

    var isEffect: Bool {
        self == .blur || self == .pixelate
    }

    var usesRectangularDrag: Bool {
        switch self {
        case .arrow, .rectangle, .oval, .line, .blur, .pixelate:
            return true
        case .text, .pencil:
            return false
        }
    }

    var icon: String {
        switch self {
        case .arrow: return "arrow.right"
        case .text: return "textformat"
        case .rectangle: return "rectangle"
        case .oval: return "circle"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .blur: return "circle.lefthalf.filled"
        case .pixelate: return "square.grid.3x3"
        }
    }
}

struct AnnotationElement: Identifiable, Equatable {
    let id: UUID
    let tool: AnnotationTool
    let points: [CGPoint]
    let color: Color
    let lineWidth: CGFloat
    let startPoint: CGPoint?
    let endPoint: CGPoint?
    let text: String?
    let fontSize: CGFloat?

    init(
        id: UUID = UUID(),
        tool: AnnotationTool,
        points: [CGPoint] = [],
        color: Color = .red,
        lineWidth: CGFloat = 2.0,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        text: String? = nil,
        fontSize: CGFloat? = nil
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.text = text
        self.fontSize = fontSize
    }

    static func == (lhs: AnnotationElement, rhs: AnnotationElement) -> Bool {
        lhs.id == rhs.id
    }
}

extension AnnotationElement {
    var effectRect: CGRect? {
        guard tool.isEffect, let startPoint, let endPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    var effectAmount: CGFloat {
        switch tool {
        case .blur:
            return max(lineWidth * 2, 6)
        case .pixelate:
            return max(lineWidth * 4, 10)
        default:
            return lineWidth
        }
    }

    static func normalized(
        tool: AnnotationTool,
        points: [CGPoint] = [],
        color: Color,
        lineWidth: CGFloat,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        in rect: CGRect
    ) -> AnnotationElement? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let baseDimension = max(min(rect.width, rect.height), 1)
        return AnnotationElement(
            tool: tool,
            points: points.map { normalize($0, in: rect) },
            color: color,
            lineWidth: lineWidth / baseDimension,
            startPoint: startPoint.map { normalize($0, in: rect) },
            endPoint: endPoint.map { normalize($0, in: rect) },
            text: text,
            fontSize: fontSize.map { $0 / baseDimension }
        )
    }

    func denormalized(in rect: CGRect) -> AnnotationElement {
        let baseDimension = max(min(rect.width, rect.height), 1)
        return AnnotationElement(
            id: id,
            tool: tool,
            points: points.map { Self.denormalize($0, in: rect) },
            color: color,
            lineWidth: max(lineWidth * baseDimension, 1),
            startPoint: startPoint.map { Self.denormalize($0, in: rect) },
            endPoint: endPoint.map { Self.denormalize($0, in: rect) },
            text: text,
            fontSize: fontSize.map { max($0 * baseDimension, 1) }
        )
    }

    static func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let normalizedX = (point.x - rect.minX) / rect.width
        let normalizedY = (point.y - rect.minY) / rect.height
        return CGPoint(x: clamp(normalizedX), y: clamp(normalizedY))
    }

    static func denormalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

/// Text being typed into the editor's text box; it becomes an annotation when committed.
struct TextDraft: Equatable {
    /// Top-leading corner of the text, normalized to the image like committed annotations.
    var origin: CGPoint
    var text: String = ""
    /// `min(width, height)` of the displayed image when the box was placed. On-screen sizes are
    /// divided by this to normalize them, the same way `AnnotationElement.normalized` does.
    var referenceDimension: CGFloat
}
