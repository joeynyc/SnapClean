import SwiftUI

struct AnnotationCanvasView: View {
    @Environment(AppState.self) var appState
    let image: NSImage

    @State private var isDrawing = false
    @State private var currentPath: [CGPoint] = []
    @State private var currentStartPoint: CGPoint = .zero
    @State private var currentEndPoint: CGPoint = .zero
    @State private var textFieldSize: CGSize = .zero
    @FocusState private var isTextFieldFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        GeometryReader { geometry in
            let imageFrame = imageDisplayFrame(in: geometry.size)
            let denormalized = appState.annotations.elements.map { $0.denormalized(in: imageFrame) }
            // Everything shares the GeometryReader's coordinate space, so the image is laid out
            // at exactly `imageFrame` and gesture locations line up with normalized annotations.
            ZStack {
                // Background
                Color(NSColor.controlBackgroundColor)

                // Base image
                Image(nsImage: image)
                    .resizable()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                // Single Canvas for all persisted annotations (more efficient than per-annotation Canvas views)
                Canvas { context, size in
                    for element in denormalized {
                        AnnotationRenderer.draw(element, in: context)
                    }
                }

                // Current drawing
                if !currentPath.isEmpty {
                    AnnotationRenderer(
                        tool: appState.annotations.selectedTool,
                        points: currentPath,
                        color: appState.annotations.selectedColor,
                        lineWidth: appState.annotations.lineWidth
                    )
                }

                // Current shape preview
                if isDrawing && appState.annotations.selectedTool.usesRectangularDrag {
                    AnnotationRenderer(
                        tool: appState.annotations.selectedTool,
                        startPoint: currentStartPoint,
                        endPoint: currentEndPoint,
                        color: appState.annotations.selectedColor,
                        lineWidth: appState.annotations.lineWidth
                    )
                }

                // Text box being typed into
                if let draft = appState.annotations.textDraft {
                    textDraftField(draft, imageFrame: imageFrame)
                }
            }
            .contentShape(Rectangle())
            // One gesture for every tool: the text tool acts on release, so there is no
            // tap-versus-drag ordering to get wrong.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard appState.annotations.selectedTool != .text else { return }

                        if !isDrawing {
                            isDrawing = true
                            currentStartPoint = value.location
                            currentEndPoint = value.location

                            if appState.annotations.selectedTool == .pencil {
                                currentPath = [value.location]
                            }
                        } else {
                            currentEndPoint = value.location

                            if appState.annotations.selectedTool == .pencil {
                                currentPath.append(value.location)
                            }
                        }
                    }
                    .onEnded { value in
                        let tool = appState.annotations.selectedTool
                        if tool == .text {
                            handleTextToolClick(at: value.startLocation, imageFrame: imageFrame)
                            return
                        }
                        defer {
                            isDrawing = false
                            currentPath = []
                        }
                        guard isDrawing else { return }

                        // A click without a drag would leave an invisible, zero-size annotation.
                        if tool == .pencil {
                            guard currentPath.count > 1 else { return }
                        } else if currentStartPoint == value.location {
                            return
                        }

                        if let element = AnnotationElement.normalized(
                            tool: tool,
                            points: tool == .pencil ? currentPath : [],
                            color: appState.annotations.selectedColor,
                            lineWidth: appState.annotations.lineWidth,
                            startPoint: tool.usesRectangularDrag ? currentStartPoint : nil,
                            endPoint: tool.usesRectangularDrag ? value.location : nil,
                            in: imageFrame
                        ) {
                            appState.annotations.addAnnotation(element)
                        }
                    }
            )
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    ToolbarView()
                }
            }
            .overlay(alignment: .bottom) {
                BottomToolbarView()
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKeyDown(event)
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    // MARK: - Text tool

    /// The editable text box. Its text starts exactly where the committed annotation will be
    /// drawn (`AnnotationRenderer` draws text with a top-leading anchor at the draft origin), and
    /// it never wraps, matching the renderer, which draws each line at its natural width.
    private func textDraftField(_ draft: TextDraft, imageFrame: CGRect) -> some View {
        let origin = AnnotationElement.denormalize(draft.origin, in: imageFrame)
        let displayDimension = max(min(imageFrame.width, imageFrame.height), 1)
        // Same value the committed element denormalizes to, so the size doesn't jump on commit.
        let fontSize = max(
            appState.annotations.lineWidth * AnnotationState.textSizeMultiplier
                * displayDimension / draft.referenceDimension,
            1
        )
        let text = Binding(
            get: { appState.annotations.textDraft?.text ?? "" },
            set: { appState.annotations.textDraft?.text = $0 }
        )

        let font = Font.system(size: fontSize, design: .rounded)
        // A vertical-axis TextField keeps wrapping at the width it was created with, so a box
        // that starts empty and grows wraps every character. Give the field a fixed width out to
        // the image's right edge, and size the visible box from a hidden Text of the same string
        // (plus room for the caret).
        let fieldWidth = max(imageFrame.maxX - origin.x, fontSize)
        return Text((appState.annotations.textDraft?.text ?? "") + "  ")
            .font(font)
            .fixedSize()
            .hidden()
            .frame(minWidth: fontSize, alignment: .leading)
            .overlay(alignment: .topLeading) {
                TextField("", text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(appState.annotations.selectedColor)
                    .focused($isTextFieldFocused)
                    .frame(width: fieldWidth, alignment: .topLeading)
            }
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(-4)
            )
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                textFieldSize = size
            }
            // A plain TextField draws its first line where the renderer draws a top-leading Text
            // (checked offscreen to within 1px), so no inset correction is needed.
            .offset(x: origin.x, y: origin.y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                // Focus after the field is in the window, or the request is dropped.
                DispatchQueue.main.async { isTextFieldFocused = true }
            }
    }

    /// With the text tool, a click places a text box; a click anywhere off the open box commits it.
    private func handleTextToolClick(at location: CGPoint, imageFrame: CGRect) {
        if let draft = appState.annotations.textDraft {
            let fieldFrame = CGRect(
                origin: AnnotationElement.denormalize(draft.origin, in: imageFrame),
                size: textFieldSize
            )
            // Clicks on the box itself (and its outline) are for placing the caret.
            if !fieldFrame.insetBy(dx: -4, dy: -4).contains(location) {
                appState.annotations.commitTextDraft()
            }
            return
        }
        guard imageFrame.contains(location) else { return }
        appState.annotations.beginTextDraft(at: location, in: imageFrame)
    }

    // MARK: - Keyboard

    /// Editor shortcuts. While a text field is being edited, Return commits the text box
    /// (Shift- or Option-Return inserts a line break), Escape cancels it, and the standard
    /// editing shortcuts (Cmd-C, Cmd-Z, ...) go to the field rather than the canvas.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Leave other windows (Preferences, History) alone.
        if let mainWindow = appState.capture.mainWindow, event.window !== mainWindow {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let fieldEditor = event.window?.firstResponder as? NSTextView

        if appState.annotations.textDraft != nil {
            switch event.keyCode {
            case Self.escapeKeyCode:
                appState.annotations.cancelTextDraft()
                return nil
            case Self.returnKeyCode, Self.keypadEnterKeyCode:
                guard let fieldEditor else { break }
                if flags.contains(.shift) || flags.contains(.option) {
                    fieldEditor.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    appState.annotations.commitTextDraft()
                }
                return nil
            default:
                break
            }
        }

        if flags == .command && key == "s" {
            appState.saveAnnotation()
            return nil
        }

        // Text editing gets Cmd-C, Cmd-Z and Shift-Cmd-Z.
        if fieldEditor != nil {
            return event
        }

        if flags == .command && key == "z" {
            appState.annotations.undo()
            return nil
        }
        if flags == [.command, .shift] && key == "z" {
            appState.annotations.redo()
            return nil
        }
        if flags == .command && key == "c" {
            if let img = appState.currentEditableImage() {
                appState.capture.screenCapture.copyToClipboard(img)
            }
            return nil
        }
        return event
    }

    // MARK: - Layout

    /// Fits the image inside the area above the bottom toolbar without upscaling it past its native size.
    private func imageDisplayFrame(in availableSize: CGSize) -> CGRect {
        let size = CGSize(width: max(availableSize.width, 1), height: max(availableSize.height, 1))
        let area = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: max(size.height - Self.bottomToolbarHeight, 1)
        ).insetBy(dx: Self.imagePadding, dy: Self.imagePadding)
        guard image.size.width > 0, image.size.height > 0, area.width > 0, area.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }

        let scale = min(area.width / image.size.width, area.height / image.size.height, 1)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(
            x: area.midX - width / 2,
            y: area.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static let bottomToolbarHeight: CGFloat = 56
    private static let imagePadding: CGFloat = 16
    private static let escapeKeyCode: UInt16 = 53
    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76
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
                let fontSize = element.fontSize ?? element.lineWidth * AnnotationState.textSizeMultiplier
                let resolved = context.resolve(
                    Text(text)
                        .font(.system(size: fontSize, design: .rounded))
                        .foregroundColor(color)
                )
                context.draw(resolved, at: point, anchor: .topLeading)
            }

        case .blur, .pixelate:
            drawEffectOverlay(element, in: context)
        }
    }

    private static func drawEffectOverlay(_ element: AnnotationElement, in context: GraphicsContext) {
        guard let rect = element.effectRect, rect.width > 0, rect.height > 0 else { return }

        let overlayColor: Color = element.tool == .blur ? .cyan : .purple
        context.fill(
            Path(rect),
            with: .color(overlayColor.opacity(0.14))
        )
        context.stroke(
            Path(rect),
            with: .color(overlayColor.opacity(0.9)),
            style: StrokeStyle(
                lineWidth: max(element.lineWidth, 2),
                lineCap: .round,
                lineJoin: .round,
                dash: [8, 5]
            )
        )
    }

    private static func drawArrow(context: GraphicsContext, start: CGPoint, end: CGPoint, color: Color, lineWidth: CGFloat) {
        guard let arrow = arrowGeometry(start: start, end: end, lineWidth: lineWidth) else { return }

        var path = Path()
        path.move(to: start)
        path.addLine(to: arrow.shaftEnd)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)

        var arrowPath = Path()
        arrowPath.move(to: arrow.tip)
        arrowPath.addLine(to: arrow.left)
        arrowPath.addLine(to: arrow.right)
        arrowPath.closeSubpath()
        context.fill(arrowPath, with: .color(color))
    }

    struct ArrowGeometry: Equatable {
        /// Where the shaft stops: inside the head, so a thick shaft's square end can't poke past its sides.
        var shaftEnd: CGPoint
        var tip: CGPoint
        var left: CGPoint
        var right: CGPoint
    }

    /// Head length per point of line width. The head scales only with the line width (which is
    /// normalized like the points), so the editor and the full-size export show the same proportions.
    static let arrowHeadLengthPerLineWidth: CGFloat = 6
    private static let arrowHeadHalfAngle: CGFloat = .pi / 6

    /// Returns nil for a zero-length arrow, which has no direction.
    static func arrowGeometry(start: CGPoint, end: CGPoint, lineWidth: CGFloat) -> ArrowGeometry? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return nil }

        // A short arrow is all head rather than a head that overshoots its start.
        let headLength = min(lineWidth * arrowHeadLengthPerLineWidth, length)
        let angle = atan2(dy, dx)
        let left = CGPoint(
            x: end.x - headLength * cos(angle - arrowHeadHalfAngle),
            y: end.y - headLength * sin(angle - arrowHeadHalfAngle)
        )
        let right = CGPoint(
            x: end.x - headLength * cos(angle + arrowHeadHalfAngle),
            y: end.y - headLength * sin(angle + arrowHeadHalfAngle)
        )
        // Halfway into the head, where it is still wider than the shaft.
        let shaftLength = length - headLength * cos(arrowHeadHalfAngle) / 2
        let shaftEnd = CGPoint(x: start.x + dx / length * shaftLength, y: start.y + dy / length * shaftLength)
        return ArrowGeometry(shaftEnd: shaftEnd, tip: end, left: left, right: right)
    }
}

struct BottomToolbarView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        HStack(spacing: 20) {
            // Left side - Actions
            HStack(spacing: 12) {
                ActionButton(icon: "xmark.circle", label: "Cancel") {
                    appState.annotations.resetAnnotationState()
                    appState.capture.showAnnotationCanvas = false
                }

                Divider()
                    .frame(height: 20)

                ActionButton(icon: "doc.on.doc", label: "Copy") {
                    guard let image = appState.currentEditableImage() else { return }
                    appState.capture.screenCapture.copyToClipboard(image)
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
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                Text("^[\(appState.annotations.elements.count) annotation](inflect: true)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .glassEffect()
            } else {
                Text("^[\(appState.annotations.elements.count) annotation](inflect: true)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            #else
            Text("^[\(appState.annotations.elements.count) annotation](inflect: true)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            #endif
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
        Image(nsImage: image)
            .resizable()
            .overlay {
                Canvas { context, size in
                    for element in annotations {
                        AnnotationRenderer.draw(element, in: context)
                    }
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
            .foregroundStyle(isHovered ? Color.accentColor : .primary)
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
        .environment(AppState())
}
