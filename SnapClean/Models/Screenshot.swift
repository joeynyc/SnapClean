import SwiftUI
import Combine
import AppKit

enum CaptureMode {
    case region
    case window
    case screen
}

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
        [.arrow, .text, .rectangle, .oval, .line, .pencil]
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

struct ScreenshotItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let filePath: String
    let thumbnail: Data?

    init(id: UUID = UUID(), date: Date = Date(), filePath: String, thumbnail: Data? = nil) {
        self.id = id
        self.date = date
        self.filePath = filePath
        self.thumbnail = thumbnail
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var isCapturing = false
    @Published var currentCaptureMode: CaptureMode = .region
    @Published var capturedImage: NSImage?
    @Published var showAnnotationCanvas = false
    @Published var showHistory = false
    @Published var showAboutWindow = false
    @Published var showPreferences = false
    @Published var showPinWindow = false
    @Published var pinnedImage: NSImage?
    @Published var screenshotHistory: [ScreenshotItem] = []

    @Published var selectedTool: AnnotationTool = .arrow
    @Published var selectedColor: Color = .red
    @Published var lineWidth: CGFloat = 2.0
    @Published var annotations: [AnnotationElement] = []
    @Published var undoStack: [[AnnotationElement]] = []
    @Published var redoStack: [[AnnotationElement]] = []
    @Published var annotationCanvasSize: CGSize = .zero

    @Published var isTransparentBackground = false
    @Published var captureCountdown: Int = 0

    let screenCapture = ScreenCaptureService()
    let historyManager = ScreenshotHistoryManager()
    private let captureOverlayController = CaptureOverlayWindowController()
    private var captureTimer: Timer?
    private var wasMainWindowVisibleBeforeCapture = false
    weak var mainWindow: NSWindow?

    var copyAfterCapture: Bool {
        get { UserDefaults.standard.bool(forKey: "copyAfterCapture") }
        set { UserDefaults.standard.set(newValue, forKey: "copyAfterCapture") }
    }

    var showPreviewAfterCapture: Bool {
        get {
            if UserDefaults.standard.object(forKey: "showPreviewAfterCapture") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "showPreviewAfterCapture")
        }
        set { UserDefaults.standard.set(newValue, forKey: "showPreviewAfterCapture") }
    }

    var timerDuration: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "timerDuration")
            return val > 0 ? val : 3
        }
        set { UserDefaults.standard.set(newValue, forKey: "timerDuration") }
    }

    var historyLimit: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "historyLimit")
            return val > 0 ? val : 50
        }
        set { UserDefaults.standard.set(newValue, forKey: "historyLimit") }
    }

    init() {
        loadHistory()
        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .startCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mode = notification.userInfo?["mode"] as? CaptureMode else { return }
            Task { @MainActor in
                self?.startCapture(mode: mode)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .openHistory,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showHistory = true
            }
        }
    }

    func startCapture(mode: CaptureMode) {
        if !CGPreflightScreenCaptureAccess() {
            requestScreenCaptureAccessIfNeeded()
            return
        }
        currentCaptureMode = mode
        isCapturing = true
        captureCountdown = 0
        wasMainWindowVisibleBeforeCapture = mainWindow?.isVisible ?? false
        mainWindow?.orderOut(nil)
        captureOverlayController.show(mode: mode, appState: self)

        if mode == .screen {
            startScreenCountdown()
        }
    }

    func handleCapturedImage(_ image: NSImage) {
        capturedImage = image
        let shouldShowMainWindow = showPreviewAfterCapture || wasMainWindowVisibleBeforeCapture
        endCapture(showMainWindow: shouldShowMainWindow)

        if copyAfterCapture {
            screenCapture.copyToClipboard(image)
        }

        if showPreviewAfterCapture {
            showAnnotationCanvas = true
        } else {
            if let path = screenCapture.saveImage(image) {
                addToHistory(path: path, image: image)
            }
        }
    }

    func cancelCapture() {
        captureTimer?.invalidate()
        captureCountdown = 0
        endCapture(showMainWindow: wasMainWindowVisibleBeforeCapture)
    }

    func endCaptureRestoringWindow() {
        endCapture(showMainWindow: wasMainWindowVisibleBeforeCapture)
    }

    func saveAnnotation() {
        let imageToSave = currentEditableImage()
        guard let imageToSave else { return }
        guard let savedPath = screenCapture.saveImage(imageToSave) else {
            NSLog("SnapClean: Failed to save annotation")
            return
        }
        addToHistory(path: savedPath, image: imageToSave)
        resetAnnotationState()
        showAnnotationCanvas = false
    }

    func addToHistory(path: String, image: NSImage) {
        let thumbnail = image.resize(to: NSSize(width: 150, height: 100))?.tiffRepresentation
        let item = ScreenshotItem(date: Date(), filePath: path, thumbnail: thumbnail)
        screenshotHistory.insert(item, at: 0)
        if screenshotHistory.count > historyLimit {
            screenshotHistory.removeLast()
        }
        historyManager.saveHistory(screenshotHistory)
    }

    func loadHistory() {
        screenshotHistory = historyManager.loadHistory()
    }

    private func startScreenCountdown() {
        captureTimer?.invalidate()
        captureCountdown = timerDuration
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.captureCountdown > 1 {
                    self.captureCountdown -= 1
                    return
                }

                self.captureCountdown = 0
                self.captureTimer?.invalidate()
                self.captureTimer = nil

                if let image = self.screenCapture.captureFullScreen() {
                    self.handleCapturedImage(image)
                } else {
                    self.endCapture(showMainWindow: self.wasMainWindowVisibleBeforeCapture)
                }
            }
        }
    }

    private func endCapture(showMainWindow: Bool) {
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
        captureCountdown = 0
        captureOverlayController.hide()

        if showMainWindow, let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func requestScreenCaptureAccessIfNeeded() {
        let key = "didRequestScreenCaptureAccess"
        if UserDefaults.standard.bool(forKey: key) == false {
            UserDefaults.standard.set(true, forKey: key)
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func addAnnotation(_ element: AnnotationElement) {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations.append(element)
    }

    func undo() {
        guard let lastState = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = lastState
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = nextState
    }

    func clearAnnotations() {
        undoStack.append(annotations)
        redoStack.removeAll()
        annotations = []
    }

    func resetAnnotationState() {
        annotations = []
        undoStack = []
        redoStack = []
    }

    func pinToScreen(_ image: NSImage) {
        pinnedImage = image
        showPinWindow = true
    }

    func currentEditableImage() -> NSImage? {
        renderAnnotatedImage() ?? capturedImage
    }

    @MainActor
    private func renderAnnotatedImage() -> NSImage? {
        guard let image = capturedImage, annotationCanvasSize != .zero else { return nil }
        guard #available(macOS 13.0, *) else { return nil }

        let exportSize = image.size
        guard exportSize.width > 0, exportSize.height > 0 else { return nil }

        let scaleX = exportSize.width / annotationCanvasSize.width
        let scaleY = exportSize.height / annotationCanvasSize.height
        let annotationScale = min(scaleX, scaleY)
        let scaledAnnotations = annotations.map { element in
            scaleAnnotation(
                element,
                scaleX: scaleX,
                scaleY: scaleY,
                annotationScale: annotationScale
            )
        }

        let content = AnnotationExportView(image: image, annotations: scaledAnnotations)
            .frame(width: exportSize.width, height: exportSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = imageBackingScale(for: image)
        return renderer.nsImage
    }

    private func imageBackingScale(for image: NSImage) -> CGFloat {
        guard image.size.width > 0 else { return NSScreen.main?.backingScaleFactor ?? 2.0 }
        if let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            let scale = CGFloat(bitmap.pixelsWide) / image.size.width
            if scale.isFinite, scale > 0 {
                return scale
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private func scaleAnnotation(
        _ element: AnnotationElement,
        scaleX: CGFloat,
        scaleY: CGFloat,
        annotationScale: CGFloat
    ) -> AnnotationElement {
        let scaledPoints = element.points.map { point in
            CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        }
        let scaledStart = element.startPoint.map { point in
            CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        }
        let scaledEnd = element.endPoint.map { point in
            CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        }
        let scaledFont = element.fontSize.map { $0 * annotationScale }

        return AnnotationElement(
            id: element.id,
            tool: element.tool,
            points: scaledPoints,
            color: element.color,
            lineWidth: element.lineWidth * annotationScale,
            startPoint: scaledStart,
            endPoint: scaledEnd,
            text: element.text,
            fontSize: scaledFont
        )
    }
}

class ScreenshotHistoryManager {
    private let historyKey = "screenshotHistory"
    let saveDirectory: URL

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveDirectory = documentsPath.appendingPathComponent("SnapClean/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
    }

    func saveHistory(_ history: [ScreenshotItem]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func loadHistory() -> [ScreenshotItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([ScreenshotItem].self, from: data) else {
            return []
        }
        return history.filter { FileManager.default.fileExists(atPath: $0.filePath) }
    }

    func deleteItem(_ item: ScreenshotItem) {
        try? FileManager.default.removeItem(atPath: item.filePath)
        _ = loadHistory()
    }
}
