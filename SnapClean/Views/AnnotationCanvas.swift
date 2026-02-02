import SwiftUI

struct AnnotationCanvasView: View {
    @EnvironmentObject var appState: AppState
    let image: NSImage

    @State private var isDrawing = false
    @State private var currentPath: [CGPoint] = []
    @State private var currentStartPoint: CGPoint = .zero
    @State private var currentEndPoint: CGPoint = .zero
    @State private var showFontPicker = false
    @State private var showExportOptions = false
    @State private var textInput = ""
    @State private var isEnteringText = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(NSColor.controlBackgroundColor)

                // Main canvas area
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack {
                        // Base image
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)

                        // Annotations layer
                        ForEach(appState.annotations) { element in
                            AnnotationRenderer(element: element)
                        }

                        // Current drawing
                        if !currentPath.isEmpty {
                            AnnotationRenderer(
                                tool: appState.selectedTool,
                                points: currentPath,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth
                            )
                        }

                        // Current shape preview
                        if isDrawing && (appState.selectedTool == .arrow || appState.selectedTool == .rectangle || appState.selectedTool == .oval || appState.selectedTool == .line) {
                            AnnotationRenderer(
                                tool: appState.selectedTool,
                                startPoint: currentStartPoint,
                                endPoint: currentEndPoint,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth
                            )
                        }

                        // Text input overlay
                        if isEnteringText {
                            TextEditor(text: $textInput)
                                .font(.system(size: appState.lineWidth * 8, design: .rounded))
                                .foregroundColor(appState.selectedColor)
                                .frame(width: 200, height: 50)
                                .position(currentEndPoint)
                                .background(Color.clear)
                                .onDisappear {
                                    if !textInput.isEmpty {
                                        let element = AnnotationElement(
                                            tool: .text,
                                            points: [currentEndPoint],
                                            color: appState.selectedColor,
                                            lineWidth: appState.lineWidth,
                                            text: textInput
                                        )
                                        appState.addAnnotation(element)
                                    }
                                    textInput = ""
                                    isEnteringText = false
                                }
                        }
                    }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    ToolbarView()
                }
            }
            .overlay(alignment: .bottom) {
                BottomToolbarView()
            }
        }
        .onTapGesture { location in
            if appState.selectedTool == .text && !isDrawing {
                currentEndPoint = location
                isEnteringText = true
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if isEnteringText {
                        currentEndPoint = value.location
                        return
                    }

                    if !isDrawing {
                        isDrawing = true
                        currentStartPoint = value.location
                        currentEndPoint = value.location

                        if appState.selectedTool == .pencil {
                            currentPath = [value.location]
                        }
                    } else {
                        currentEndPoint = value.location

                        if appState.selectedTool == .pencil {
                            currentPath.append(value.location)
                        }
                    }
                }
                .onEnded { value in
                    if isEnteringText {
                        return
                    }

                    let element: AnnotationElement?
                    switch appState.selectedTool {
                    case .arrow:
                        element = AnnotationElement(
                            tool: .arrow,
                            color: appState.selectedColor,
                            lineWidth: appState.lineWidth,
                            startPoint: currentStartPoint,
                            endPoint: value.location
                        )
                    case .rectangle:
                        element = AnnotationElement(
                            tool: .rectangle,
                            color: appState.selectedColor,
                            lineWidth: appState.lineWidth,
                            startPoint: currentStartPoint,
                            endPoint: value.location
                        )
                    case .oval:
                        element = AnnotationElement(
                            tool: .oval,
                            color: appState.selectedColor,
                            lineWidth: appState.lineWidth,
                            startPoint: currentStartPoint,
                            endPoint: value.location
                        )
                    case .line:
                        element = AnnotationElement(
                            tool: .line,
                            color: appState.selectedColor,
                            lineWidth: appState.lineWidth,
                            startPoint: currentStartPoint,
                            endPoint: value.location
                        )
                    case .pencil:
                        element = AnnotationElement(
                            tool: .pencil,
                            points: currentPath,
                            color: appState.selectedColor,
                            lineWidth: appState.lineWidth
                        )
                    default:
                        element = nil
                    }

                    if let el = element {
                        appState.addAnnotation(el)
                    }

                    isDrawing = false
                    currentPath = []
                }
        )
        .keyboardShortcut("z", modifiers: .command)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .keyboardShortcut("s", modifiers: .command)
        .keyboardShortcut("c", modifiers: .command)
    }

    private func saveImage() {
        appState.saveAnnotation()
    }

    private func copyToClipboard() {
        appState.screenCapture.copyToClipboard(image)
    }
}

struct AnnotationRenderer: View {
    let element: AnnotationElement?

    init(element: AnnotationElement) {
        self.element = element
    }

    init(tool: AnnotationTool, points: [CGPoint], color: Color, lineWidth: CGFloat) {
        self.element = AnnotationElement(
            tool: tool,
            points: points,
            color: color,
            lineWidth: lineWidth
        )
    }

    init(tool: AnnotationTool, startPoint: CGPoint, endPoint: CGPoint, color: Color, lineWidth: CGFloat) {
        self.element = AnnotationElement(
            tool: tool,
            color: color,
            lineWidth: lineWidth,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    var body: some View {
        if let el = element {
            Canvas { context, size in
                let color = Color(el.color)

                switch el.tool {
                case .arrow:
                    drawArrow(context: context, start: el.startPoint ?? .zero, end: el.endPoint ?? .zero, color: color, lineWidth: el.lineWidth)

                case .rectangle:
                    if let start = el.startPoint, let end = el.endPoint {
                        let rect = CGRect(
                            x: min(start.x, end.x),
                            y: min(start.y, end.y),
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        context.stroke(
                            Path(rect),
                            with: .color(color),
                            lineWidth: el.lineWidth
                        )
                    }

                case .oval:
                    if let start = el.startPoint, let end = el.endPoint {
                        let rect = CGRect(
                            x: min(start.x, end.x),
                            y: min(start.y, end.y),
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(color),
                            lineWidth: el.lineWidth
                        )
                    }

                case .line:
                    if let start = el.startPoint, let end = el.endPoint {
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        context.stroke(path, with: .color(color), lineWidth: el.lineWidth)
                    }

                case .pencil:
                    if el.points.count > 1 {
                        var path = Path()
                        path.move(to: el.points[0])
                        for point in el.points.dropFirst() {
                            path.addLine(to: point)
                        }
                        context.stroke(path, with: .color(color), lineWidth: el.lineWidth)
                    }

                case .text:
                    if let text = el.text, let point = el.points.first {
                        let font = NSFont.systemFont(ofSize: el.fontSize ?? el.lineWidth * 8)
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: color
                        ]
                        let attributedString = NSAttributedString(string: text, attributes: attributes)
                        attributedString.draw(at: CGPoint(x: point.x, y: point.y - (el.fontSize ?? el.lineWidth * 8)))
                    }

                case .blur, .pixelate:
                    break
                }
            }
        }
    }

    private func drawArrow(context: GraphicsContext, start: CGPoint, end: CGPoint, color: Color, lineWidth: CGFloat) {
        // Draw line
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)

        // Draw arrowhead
        let arrowLength: CGFloat = 15
        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrowTip = end
        let leftPoint = CGPoint(
            x: end.x - arrowLength * cos(angle - .pi / 6),
            y: end.y - arrowLength * sin(angle - .pi / 6)
        )
        let rightPoint = CGPoint(
            x: end.x - arrowLength * cos(angle + .pi / 6),
            y: end.y - arrowLength * sin(angle + .pi / 6)
        )

        var arrowPath = Path()
        arrowPath.move(to: arrowTip)
        arrowPath.addLine(to: leftPoint)
        arrowPath.addLine(to: rightPoint)
        arrowPath.closeSubpath()
        context.fill(arrowPath, with: .color(color))
    }
}

struct BottomToolbarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 20) {
            // Left side - Actions
            HStack(spacing: 12) {
                ActionButton(icon: "xmark.circle", label: "Cancel") {
                    appState.resetAnnotationState()
                    appState.showAnnotationCanvas = false
                }

                Divider()
                    .frame(height: 20)

                ActionButton(icon: "doc.on.doc", label: "Copy") {
                    appState.screenCapture.copyToClipboard(appState.capturedImage ?? NSImage())
                }

                ActionButton(icon: "square.and.arrow.down", label: "Save") {
                    appState.saveAnnotation()
                }

                ActionButton(icon: "pin", label: "Pin") {
                    if let image = appState.capturedImage {
                        appState.pinToScreen(image)
                    }
                }
            }

            Spacer()

            // Right side - Status
            if #available(macOS 26, *) {
                Text("\(appState.annotations.count) annotations")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .glassEffect()
            } else {
                Text("\(appState.annotations.count) annotations")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(isHovered ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    AnnotationCanvasView(image: NSImage())
        .environmentObject(AppState())
}
