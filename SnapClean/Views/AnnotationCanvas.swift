import SwiftUI

struct AnnotationCanvasView: View {
    @EnvironmentObject var appState: AppState
    let image: NSImage

    @State private var isDrawing = false
    @State private var currentPath: [CGPoint] = []
    @State private var currentStartPoint: CGPoint = .zero
    @State private var currentEndPoint: CGPoint = .zero
    @State private var textInput = ""
    @State private var isEnteringText = false
    @State private var keyMonitor: Any?

    var body: some View {
        GeometryReader { geometry in
            let imageFrame = imageDisplayFrame(in: geometry.size)
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

                        // Single Canvas for all persisted annotations (more efficient than per-annotation Canvas views)
                        Canvas { context, size in
                            for element in appState.annotations {
                                let denormalized = element.denormalized(in: imageFrame)
                                AnnotationRenderer.draw(denormalized, in: context)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                                        let fontSize = appState.lineWidth * 8
                                        if let element = AnnotationElement.normalized(
                                            tool: .text,
                                            points: [currentEndPoint],
                                            color: appState.selectedColor,
                                            lineWidth: appState.lineWidth,
                                            text: textInput,
                                            fontSize: fontSize,
                                            in: imageFrame
                                        ) {
                                            appState.addAnnotation(element)
                                        }
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
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if appState.selectedTool == .text && !isDrawing {
                            currentEndPoint = value.location
                            isEnteringText = true
                        }
                    }
            )
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
                            element = AnnotationElement.normalized(
                                tool: .arrow,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth,
                                startPoint: currentStartPoint,
                                endPoint: value.location,
                                in: imageFrame
                            )
                        case .rectangle:
                            element = AnnotationElement.normalized(
                                tool: .rectangle,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth,
                                startPoint: currentStartPoint,
                                endPoint: value.location,
                                in: imageFrame
                            )
                        case .oval:
                            element = AnnotationElement.normalized(
                                tool: .oval,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth,
                                startPoint: currentStartPoint,
                                endPoint: value.location,
                                in: imageFrame
                            )
                        case .line:
                            element = AnnotationElement.normalized(
                                tool: .line,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth,
                                startPoint: currentStartPoint,
                                endPoint: value.location,
                                in: imageFrame
                            )
                        case .pencil:
                            element = AnnotationElement.normalized(
                                tool: .pencil,
                                points: currentPath,
                                color: appState.selectedColor,
                                lineWidth: appState.lineWidth,
                                in: imageFrame
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
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags == .command && event.charactersIgnoringModifiers == "z" {
                    appState.undo()
                    return nil
                }
                if flags == [.command, .shift] && event.charactersIgnoringModifiers == "z" {
                    appState.redo()
                    return nil
                }
                if flags == .command && event.charactersIgnoringModifiers == "s" {
                    appState.saveAnnotation()
                    return nil
                }
                if flags == .command && event.charactersIgnoringModifiers == "c" {
                    if let img = appState.currentEditableImage() {
                        appState.screenCapture.copyToClipboard(img)
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    private func geometrySizeClamped(to size: CGSize) -> CGSize {
        CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    private func imageDisplayFrame(in availableSize: CGSize) -> CGRect {
        let size = geometrySizeClamped(to: availableSize)
        guard image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}

struct AnnotationRenderer: View {
    let element: AnnotationElement

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
        Canvas { context, size in
            AnnotationRenderer.draw(element, in: context)
        }
    }

    static func draw(_ element: AnnotationElement, in context: GraphicsContext) {
        let color = element.color

        switch element.tool {
        case .arrow:
            drawArrow(context: context, start: element.startPoint ?? .zero, end: element.endPoint ?? .zero, color: color, lineWidth: element.lineWidth)

        case .rectangle:
            if let start = element.startPoint, let end = element.endPoint {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.stroke(
                    Path(rect),
                    with: .color(color),
                    lineWidth: element.lineWidth
                )
            }

        case .oval:
            if let start = element.startPoint, let end = element.endPoint {
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color),
                    lineWidth: element.lineWidth
                )
            }

        case .line:
            if let start = element.startPoint, let end = element.endPoint {
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(color), lineWidth: element.lineWidth)
            }

        case .pencil:
            if element.points.count > 1 {
                var path = Path()
                path.move(to: element.points[0])
                for point in element.points.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(path, with: .color(color), lineWidth: element.lineWidth)
            }

        case .text:
            if let text = element.text, let point = element.points.first {
                let fontSize = element.fontSize ?? element.lineWidth * 8
                let resolved = context.resolve(
                    Text(text)
                        .font(.system(size: fontSize, design: .rounded))
                        .foregroundColor(color)
                )
                context.draw(resolved, at: point, anchor: .topLeading)
            }

        case .blur, .pixelate:
            break
        }
    }

    private static func drawArrow(context: GraphicsContext, start: CGPoint, end: CGPoint, color: Color, lineWidth: CGFloat) {
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
                    guard let image = appState.currentEditableImage() else { return }
                    appState.screenCapture.copyToClipboard(image)
                }

                ActionButton(icon: "square.and.arrow.down", label: "Save") {
                    appState.saveAnnotation()
                }

                ActionButton(icon: "pin", label: "Pin") {
                    if let image = appState.currentEditableImage() {
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

struct AnnotationExportView: View {
    let image: NSImage
    let annotations: [AnnotationElement]

    var body: some View {
        ZStack {
            Color.clear
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            ForEach(annotations) { element in
                AnnotationRenderer(element: element)
            }
        }
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
