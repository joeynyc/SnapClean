import SwiftUI
import AppKit
import ScreenCaptureKit
import os

private let appLogger = Logger(subsystem: "com.snapclean.app", category: "app")
private let historyLogger = Logger(subsystem: "com.snapclean.app", category: "history")

enum CaptureMode {
    case region
    case window
    case screen
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case captureFailed(CaptureMode)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission is required to capture screenshots."
        case .captureFailed(let mode):
            return "Failed to capture \(mode). The screen content may be protected."
        case .saveFailed(let path):
            return "Failed to save screenshot to \(path)."
        }
    }
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

// MARK: - CaptureState

@Observable @MainActor
final class CaptureState {
    var isCapturing = false
    var currentCaptureMode: CaptureMode = .region
    var capturedImage: NSImage?
    var showAnnotationCanvas = false
    var captureCountdown: Int = 0
    private(set) var screenCapturePermissionStatus: ScreenCapturePermissionStatus = .unknown
    var lastCaptureError: CaptureError?

    let screenCapture: ScreenCapturing
    @ObservationIgnored let captureOverlayController = CaptureOverlayWindowController()
    @ObservationIgnored private let screenCaptureAccessPromptedKey = "didPromptScreenCaptureAccess"
    @ObservationIgnored var wasMainWindowVisibleBeforeCapture = false
    @ObservationIgnored weak var mainWindow: NSWindow?

    init(screenCapture: ScreenCapturing = ScreenCaptureService()) {
        self.screenCapture = screenCapture
    }

    func endCapture(showMainWindow: Bool) {
        isCapturing = false
        captureCountdown = 0
        captureOverlayController.hide()
        if showMainWindow, let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refreshScreenCapturePermissionStatus() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await currentScreenCaptureAccess() {
                screenCapturePermissionStatus = .granted
            } else if UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) {
                screenCapturePermissionStatus = .denied
            } else {
                screenCapturePermissionStatus = .unknown
            }
        }
    }

    func openScreenCaptureSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        _ = NSWorkspace.shared.open(settingsURL)
    }

    func currentScreenCaptureAccess() async -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    func requestScreenCaptureAccess() -> Bool {
        UserDefaults.standard.set(true, forKey: screenCaptureAccessPromptedKey)
        let granted = CGRequestScreenCaptureAccess()
        screenCapturePermissionStatus = granted ? .granted : .denied
        return granted
    }

    func revealMainWindowForPermissionGuidance() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - AnnotationState

@Observable @MainActor
final class AnnotationState {
    @ObservationIgnored private let maxUndoRedoDepth = 30

    var selectedTool: AnnotationTool = .arrow
    var selectedColor: Color = .red
    var lineWidth: CGFloat = 2.0
    var elements: [AnnotationElement] = []
    var undoStack: [[AnnotationElement]] = []
    var redoStack: [[AnnotationElement]] = []

    func addAnnotation(_ element: AnnotationElement) {
        undoStack.append(elements)
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        elements.append(element)
    }

    func undo() {
        guard let lastState = undoStack.popLast() else { return }
        redoStack.append(elements)
        if redoStack.count > maxUndoRedoDepth {
            redoStack.removeFirst()
        }
        elements = lastState
    }

    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(elements)
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        elements = nextState
    }

    func clearAnnotations() {
        undoStack.append(elements)
        if undoStack.count > maxUndoRedoDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        elements = []
    }

    func resetAnnotationState() {
        elements = []
        undoStack = []
        redoStack = []
    }
}

// MARK: - HistoryState

@Observable @MainActor
final class HistoryState {
    var screenshotHistory: [ScreenshotItem] = []
    let historyManager: HistoryPersisting

    init(historyManager: HistoryPersisting = ScreenshotHistoryManager()) {
        self.historyManager = historyManager
    }

    func addToHistory(path: String, image: NSImage, limit: Int) {
        let itemID = UUID()
        let capturedAt = Date()

        let item = ScreenshotItem(id: itemID, date: capturedAt, filePath: path, thumbnail: nil)
        screenshotHistory.insert(item, at: 0)
        let removed = trimHistoryToLimit(limit: limit)
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

    func loadHistory(limit: Int) {
        screenshotHistory = historyManager.loadHistory()
        let removed = trimHistoryToLimit(limit: limit)
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

    private func trimHistoryToLimit(limit: Int) -> [ScreenshotItem] {
        guard screenshotHistory.count > limit else { return [] }
        let overflow = Array(screenshotHistory.suffix(from: limit))
        screenshotHistory.removeLast(overflow.count)
        return overflow
    }
}

// MARK: - AppState (Coordinator)

@Observable @MainActor
final class AppState {
    let capture: CaptureState
    let annotations: AnnotationState
    let history: HistoryState

    var showAboutWindow = false
    var showPreferences = false
    var showHistory = false
    var showPinWindow = false
    var pinnedImage: NSImage?
    var isTransparentBackground = false

    // Preferences (stored properties synced to UserDefaults via didSet)
    var copyAfterCapture: Bool = false {
        didSet { UserDefaults.standard.set(copyAfterCapture, forKey: "copyAfterCapture") }
    }
    var showPreviewAfterCapture: Bool = true {
        didSet { UserDefaults.standard.set(showPreviewAfterCapture, forKey: "showPreviewAfterCapture") }
    }
    var timerDuration: Int = 3 {
        didSet { UserDefaults.standard.set(timerDuration, forKey: "timerDuration") }
    }
    var historyLimit: Int = 50 {
        didSet {
            let clamped = min(max(historyLimit, 1), 1000)
            if historyLimit != clamped {
                historyLimit = clamped
                return
            }
            UserDefaults.standard.set(historyLimit, forKey: "historyLimit")
        }
    }

    @ObservationIgnored private var captureTimer: Timer?

    init(screenCapture: ScreenCapturing = ScreenCaptureService(),
         historyManager: HistoryPersisting = ScreenshotHistoryManager()) {
        self.capture = CaptureState(screenCapture: screenCapture)
        self.annotations = AnnotationState()
        self.history = HistoryState(historyManager: historyManager)

        // Load preferences from UserDefaults
        self.copyAfterCapture = UserDefaults.standard.bool(forKey: "copyAfterCapture")
        self.showPreviewAfterCapture = UserDefaults.standard.object(forKey: "showPreviewAfterCapture") == nil
            ? true : UserDefaults.standard.bool(forKey: "showPreviewAfterCapture")
        let rawTimer = UserDefaults.standard.integer(forKey: "timerDuration")
        self.timerDuration = rawTimer > 0 ? rawTimer : 3
        let rawLimit = UserDefaults.standard.integer(forKey: "historyLimit")
        self.historyLimit = rawLimit > 0 ? rawLimit : 50

        history.loadHistory(limit: historyLimit)
        setupNotifications()
        capture.refreshScreenCapturePermissionStatus()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.capture.refreshScreenCapturePermissionStatus()
            }
        }
    }

    // MARK: - Cross-cutting Methods

    func startCapture(mode: CaptureMode) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let hasAccess = await capture.currentScreenCaptureAccess()
            if !hasAccess {
                if !capture.requestScreenCaptureAccess() {
                    capture.lastCaptureError = .permissionDenied
                    appLogger.warning("Screen capture permission denied")
                    capture.revealMainWindowForPermissionGuidance()
                    return
                }

                let grantedAfterRequest = await capture.currentScreenCaptureAccess()
                if !grantedAfterRequest {
                    capture.revealMainWindowForPermissionGuidance()
                    return
                }
            }

            beginCapture(mode: mode)
        }
    }

    func handleCapturedImage(_ image: NSImage) {
        capture.capturedImage = image
        let shouldShowMainWindow = showPreviewAfterCapture || capture.wasMainWindowVisibleBeforeCapture
        captureTimer?.invalidate()
        captureTimer = nil
        capture.endCapture(showMainWindow: shouldShowMainWindow)

        if copyAfterCapture {
            capture.screenCapture.copyToClipboard(image)
        }

        if showPreviewAfterCapture {
            capture.showAnnotationCanvas = true
        } else {
            if let path = capture.screenCapture.saveImage(image, to: history.historyManager.saveDirectory) {
                history.addToHistory(path: path, image: image, limit: historyLimit)
            } else {
                capture.lastCaptureError = .saveFailed(history.historyManager.saveDirectory.path)
                appLogger.error("Failed to save captured image to \(self.history.historyManager.saveDirectory.path, privacy: .public)")
            }
        }
    }

    func cancelCapture() {
        captureTimer?.invalidate()
        captureTimer = nil
        capture.captureCountdown = 0
        capture.endCapture(showMainWindow: capture.wasMainWindowVisibleBeforeCapture)
    }

    func endCaptureRestoringWindow() {
        captureTimer?.invalidate()
        captureTimer = nil
        capture.endCapture(showMainWindow: capture.wasMainWindowVisibleBeforeCapture)
    }

    func saveAnnotation() {
        let imageToSave = currentEditableImage()
        guard let imageToSave else { return }
        guard let savedPath = capture.screenCapture.saveImage(imageToSave, to: history.historyManager.saveDirectory) else {
            appLogger.error("Failed to save annotation")
            return
        }
        history.addToHistory(path: savedPath, image: imageToSave, limit: historyLimit)
        annotations.resetAnnotationState()
        capture.showAnnotationCanvas = false
    }

    func addToHistory(path: String, image: NSImage) {
        history.addToHistory(path: path, image: image, limit: historyLimit)
    }

    func pinToScreen(_ image: NSImage) {
        pinnedImage = image
        showPinWindow = true
    }

    func currentEditableImage() -> NSImage? {
        renderAnnotatedImage() ?? capture.capturedImage
    }

    // MARK: - Private Helpers

    @MainActor
    private func renderAnnotatedImage() -> NSImage? {
        guard let image = capture.capturedImage else { return nil }
        guard #available(macOS 13.0, *) else { return nil }

        let exportSize = image.size
        guard exportSize.width > 0, exportSize.height > 0 else { return nil }

        let exportRect = CGRect(origin: .zero, size: exportSize)
        let scaledAnnotations = annotations.elements.map { $0.denormalized(in: exportRect) }

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

    private func beginCapture(mode: CaptureMode) {
        capture.currentCaptureMode = mode
        capture.isCapturing = true
        capture.captureCountdown = 0
        capture.wasMainWindowVisibleBeforeCapture = capture.mainWindow?.isVisible ?? false
        capture.mainWindow?.orderOut(nil)
        capture.captureOverlayController.show(mode: mode, appState: self)

        if mode == .screen {
            startScreenCountdown()
        }
    }

    private func startScreenCountdown() {
        captureTimer?.invalidate()
        capture.captureCountdown = timerDuration
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.capture.captureCountdown > 1 {
                    self.capture.captureCountdown -= 1
                    return
                }

                self.capture.captureCountdown = 0
                self.captureTimer?.invalidate()
                self.captureTimer = nil

                if let image = self.capture.screenCapture.captureFullScreen() {
                    self.handleCapturedImage(image)
                } else {
                    self.capture.endCapture(showMainWindow: self.capture.wasMainWindowVisibleBeforeCapture)
                }
            }
        }
    }
}

// MARK: - ScreenshotHistoryManager

class ScreenshotHistoryManager: HistoryPersisting {
    static var defaultSaveDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("SnapClean/History", isDirectory: true)
    }

    private let historyKey = "screenshotHistory"
    private let historyFileName = "history.json"
    private let ioQueue = DispatchQueue(label: "com.snapclean.history-io", qos: .utility)
    let saveDirectory: URL
    private let historyFileURL: URL

    /// Validates that a file path is within the allowed save directory
    func isPathAllowed(_ path: String) -> Bool {
        path.hasPrefix(saveDirectory.path)
    }

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
                // Set restrictive file permissions (owner-only read/write)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyFileURL.path)
            } catch {
                historyLogger.error("Failed to save history: \(error.localizedDescription, privacy: .private)")
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
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let allowedPrefix = self.saveDirectory.path
            for path in uniquePaths where FileManager.default.fileExists(atPath: path) {
                // Security: only allow deletion of files within the intended save directory
                guard path.hasPrefix(allowedPrefix) else {
                    historyLogger.warning("Attempted to delete file outside save directory")
                    continue
                }
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
            historyLogger.error("Failed to migrate history store: \(error.localizedDescription, privacy: .private)")
        }
    }
}
