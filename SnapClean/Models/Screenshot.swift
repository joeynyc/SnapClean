import SwiftUI
import Combine
import AppKit

enum CaptureMode {
    case region
    case window
    case screen
}

enum ScreenCapturePermissionStatus {
    case unknown
    case granted
    case denied
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

extension AnnotationElement {
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

    private static func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let normalizedX = (point.x - rect.minX) / rect.width
        let normalizedY = (point.y - rect.minY) / rect.height
        return CGPoint(x: clamp(normalizedX), y: clamp(normalizedY))
    }

    private static func denormalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
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

    @Published var isTransparentBackground = false
    @Published var captureCountdown: Int = 0
    @Published private(set) var screenCapturePermissionStatus: ScreenCapturePermissionStatus = .unknown

    let screenCapture = ScreenCaptureService()
    let historyManager = ScreenshotHistoryManager()
    private let captureOverlayController = CaptureOverlayWindowController()
    private let screenCaptureAccessPromptedKey = "didPromptScreenCaptureAccess"
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
        refreshScreenCapturePermissionStatus()
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

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenCapturePermissionStatus()
            }
        }
    }

    func startCapture(mode: CaptureMode) {
        if !hasScreenCaptureAccess() {
            if !requestScreenCaptureAccess() {
                screenCapturePermissionStatus = .denied
                revealMainWindowForPermissionGuidance()
            }
            return
        }
        screenCapturePermissionStatus = .granted
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
            if let path = screenCapture.saveImage(image, to: historyManager.saveDirectory) {
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
        guard let savedPath = screenCapture.saveImage(imageToSave, to: historyManager.saveDirectory) else {
            NSLog("SnapClean: Failed to save annotation")
            return
        }
        addToHistory(path: savedPath, image: imageToSave)
        resetAnnotationState()
        showAnnotationCanvas = false
    }

    func addToHistory(path: String, image: NSImage) {
        let itemID = UUID()
        let capturedAt = Date()

        let item = ScreenshotItem(id: itemID, date: capturedAt, filePath: path, thumbnail: nil)
        screenshotHistory.insert(item, at: 0)
        let removed = trimHistoryToLimit()
        historyManager.saveHistory(screenshotHistory)
        if !removed.isEmpty {
            historyManager.removeFiles(atPaths: removed.map(\.filePath))
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let thumbnail = image.jpegThumbnailData(maxSize: NSSize(width: 300, height: 200))
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let index = self.screenshotHistory.firstIndex(where: { $0.id == itemID }) else {
                    return
                }
                self.screenshotHistory[index] = ScreenshotItem(
                    id: itemID,
                    date: capturedAt,
                    filePath: path,
                    thumbnail: thumbnail
                )
                self.historyManager.saveHistory(self.screenshotHistory)
            }
        }
    }

    func loadHistory() {
        screenshotHistory = historyManager.loadHistory()
        let removed = trimHistoryToLimit()
        historyManager.saveHistory(screenshotHistory)
        if !removed.isEmpty {
            historyManager.removeFiles(atPaths: removed.map(\.filePath))
        }
    }

    func clearHistory() {
        let removed = screenshotHistory
        screenshotHistory.removeAll()
        historyManager.saveHistory([])
        historyManager.removeFiles(atPaths: removed.map(\.filePath))
    }

    func deleteHistoryItem(_ item: ScreenshotItem) {
        screenshotHistory.removeAll { $0.id == item.id }
        historyManager.saveHistory(screenshotHistory)
        historyManager.removeFiles(atPaths: [item.filePath])
    }

    private func trimHistoryToLimit() -> [ScreenshotItem] {
        guard screenshotHistory.count > historyLimit else { return [] }
        let overflow = Array(screenshotHistory.suffix(from: historyLimit))
        screenshotHistory.removeLast(overflow.count)
        return overflow
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

    func refreshScreenCapturePermissionStatus() {
        if hasScreenCaptureAccess() {
            screenCapturePermissionStatus = .granted
        } else if UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) {
            screenCapturePermissionStatus = .denied
        } else {
            screenCapturePermissionStatus = .unknown
        }
    }

    func openScreenCaptureSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        _ = NSWorkspace.shared.open(settingsURL)
    }

    private func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func requestScreenCaptureAccess() -> Bool {
        UserDefaults.standard.set(true, forKey: screenCaptureAccessPromptedKey)
        let granted = CGRequestScreenCaptureAccess()
        screenCapturePermissionStatus = granted ? .granted : .denied
        return granted
    }

    private func revealMainWindowForPermissionGuidance() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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
        guard let image = capturedImage else { return nil }
        guard #available(macOS 13.0, *) else { return nil }

        let exportSize = image.size
        guard exportSize.width > 0, exportSize.height > 0 else { return nil }

        let exportRect = CGRect(origin: .zero, size: exportSize)
        let scaledAnnotations = annotations.map { $0.denormalized(in: exportRect) }

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

}

class ScreenshotHistoryManager {
    static var defaultSaveDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("SnapClean/History", isDirectory: true)
    }

    private let historyKey = "screenshotHistory"
    private let historyFileName = "history.json"
    private let ioQueue = DispatchQueue(label: "com.snapclean.history-io", qos: .utility)
    let saveDirectory: URL
    private let historyFileURL: URL

    init(saveDirectory: URL = ScreenshotHistoryManager.defaultSaveDirectory) {
        self.saveDirectory = saveDirectory
        historyFileURL = saveDirectory.appendingPathComponent(historyFileName)
        try? FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        migrateFromLegacyUserDefaultsIfNeeded()
    }

    func saveHistory(_ history: [ScreenshotItem]) {
        ioQueue.async { [historyFileURL] in
            do {
                let data = try JSONEncoder().encode(history)
                try data.write(to: historyFileURL, options: .atomic)
            } catch {
                NSLog("SnapClean: Failed to save history: \(error.localizedDescription)")
            }
        }
    }

    func loadHistory() -> [ScreenshotItem] {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: historyFileURL),
                  let history = try? JSONDecoder().decode([ScreenshotItem].self, from: data) else {
                return []
            }
            return history.filter { FileManager.default.fileExists(atPath: $0.filePath) }
        }
    }

    func removeFiles(atPaths paths: [String]) {
        let uniquePaths = Array(Set(paths))
        ioQueue.async {
            for path in uniquePaths where FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    private func migrateFromLegacyUserDefaultsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: historyFileURL.path),
              let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([ScreenshotItem].self, from: data) else {
            return
        }

        do {
            let encoded = try JSONEncoder().encode(history)
            try encoded.write(to: historyFileURL, options: .atomic)
            UserDefaults.standard.removeObject(forKey: historyKey)
        } catch {
            NSLog("SnapClean: Failed to migrate history store: \(error.localizedDescription)")
        }
    }
}
