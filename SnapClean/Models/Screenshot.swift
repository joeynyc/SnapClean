import SwiftUI
import AppKit
import ScreenCaptureKit
import os

private let appLogger = Logger(subsystem: "com.snapclean.app", category: "app")
private let historyLogger = Logger(subsystem: "com.snapclean.app", category: "history")

enum CaptureMode: String, CaseIterable {
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
    case checking
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
    /// Opens the main window scene when no main window exists yet; set from a SwiftUI view that has `openWindow`.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    init(screenCapture: ScreenCapturing = ScreenCaptureService()) {
        self.screenCapture = screenCapture
    }

    func endCapture(showMainWindow: Bool) {
        isCapturing = false
        captureCountdown = 0
        captureOverlayController.hide()
        if showMainWindow {
            revealMainWindow()
        }
    }

    func revealMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate()
    }

    func refreshScreenCapturePermissionStatus() {
        if currentScreenCaptureAccess() {
            screenCapturePermissionStatus = .granted
            lastCaptureError = nil
            return
        }

        guard UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) else {
            screenCapturePermissionStatus = .unknown
            return
        }

        screenCapturePermissionStatus = .checking
        Task { @MainActor in
            let hasAccess = await reconcileScreenCaptureAccessWithScreenCaptureKit()
            if !Task.isCancelled && !hasAccess {
                screenCapturePermissionStatus = .denied
            }
        }
    }

    func recheckScreenCapturePermissionStatus() {
        screenCapturePermissionStatus = .checking
        Task { @MainActor in
            if await hasUsableScreenCaptureAccess() {
                return
            }

            screenCapturePermissionStatus = UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey)
                ? .denied
                : .unknown
        }
    }

    func openScreenCaptureSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        _ = NSWorkspace.shared.open(settingsURL)
    }

    func currentScreenCaptureAccess() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    func hasUsableScreenCaptureAccess() async -> Bool {
        if currentScreenCaptureAccess() {
            screenCapturePermissionStatus = .granted
            lastCaptureError = nil
            return true
        }

        if UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) {
            screenCapturePermissionStatus = .checking
        }
        return await reconcileScreenCaptureAccessWithScreenCaptureKit()
    }

    private func reconcileScreenCaptureAccessWithScreenCaptureKit() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let hasUsableContent = !content.displays.isEmpty
            if hasUsableContent {
                screenCapturePermissionStatus = .granted
                lastCaptureError = nil
            }
            return hasUsableContent
        } catch {
            appLogger.error("ScreenCaptureKit permission check failed: \(error.localizedDescription, privacy: .private)")
            if UserDefaults.standard.bool(forKey: screenCaptureAccessPromptedKey) {
                screenCapturePermissionStatus = .denied
            }
            return false
        }
    }

    func requestScreenCaptureAccess() -> Bool {
        UserDefaults.standard.set(true, forKey: screenCaptureAccessPromptedKey)
        let granted = CGRequestScreenCaptureAccess()
        screenCapturePermissionStatus = granted ? .granted : .denied
        if granted {
            lastCaptureError = nil
        }
        return granted
    }

    func revealMainWindowForPermissionGuidance() {
        revealMainWindow()
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
    private(set) var canUndo: Bool = false
    private(set) var canRedo: Bool = false

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
        elements = []
        undoStack = []
        redoStack = []
        canUndo = false
        canRedo = false
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

    func loadHistory(limit: Int) async {
        screenshotHistory = await historyManager.loadHistory()
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
        historyManager.trashFile(atPath: item.filePath)
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

    var showPinWindow = false {
        didSet { updatePinWindow() }
    }
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
    /// Custom global shortcuts; modes without an entry use `HotkeyShortcut.defaultShortcut(for:)`.
    private(set) var shortcuts: [CaptureMode: HotkeyShortcut] = [:]
    /// While true, global hotkeys are unregistered so the shortcut recorder receives every key press.
    var isRecordingShortcut = false {
        didSet { onHotkeysChanged?() }
    }
    /// Set by AppDelegate to re-register global hotkeys when shortcuts change.
    @ObservationIgnored var onHotkeysChanged: (() -> Void)?

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
    @ObservationIgnored private let pinWindowController = PinWindowController()

    init(screenCapture: ScreenCapturing = ScreenCaptureService(),
         historyManager: HistoryPersisting = ScreenshotHistoryManager()) {
        self.capture = CaptureState(screenCapture: screenCapture)
        self.annotations = AnnotationState()
        self.history = HistoryState(historyManager: historyManager)

        // Load preferences from UserDefaults
        self.copyAfterCapture = UserDefaults.standard.bool(forKey: "copyAfterCapture")
        self.showPreviewAfterCapture = UserDefaults.standard.object(forKey: "showPreviewAfterCapture") == nil
            ? true : UserDefaults.standard.bool(forKey: "showPreviewAfterCapture")
        self.timerDuration = UserDefaults.standard.object(forKey: "timerDuration") == nil
            ? 3 : max(UserDefaults.standard.integer(forKey: "timerDuration"), 0)
        let rawLimit = UserDefaults.standard.integer(forKey: "historyLimit")
        self.historyLimit = rawLimit > 0 ? rawLimit : 50
        for mode in CaptureMode.allCases {
            if let data = UserDefaults.standard.data(forKey: Self.shortcutDefaultsKey(for: mode)),
               let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data) {
                shortcuts[mode] = shortcut
            }
        }

        Task { @MainActor in
            await history.loadHistory(limit: historyLimit)
        }
        setupNotifications()
        capture.refreshScreenCapturePermissionStatus()
        pinWindowController.onClose = { [weak self] in
            self?.showPinWindow = false
            self?.pinnedImage = nil
        }
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

    // MARK: - Shortcuts

    func shortcut(for mode: CaptureMode) -> HotkeyShortcut {
        shortcuts[mode] ?? HotkeyShortcut.defaultShortcut(for: mode)
    }

    /// Assigns a shortcut, returning false if another capture mode already uses it.
    @discardableResult
    func setShortcut(_ shortcut: HotkeyShortcut, for mode: CaptureMode) -> Bool {
        let isTaken = CaptureMode.allCases.contains { other in
            other != mode
                && self.shortcut(for: other).keyCode == shortcut.keyCode
                && self.shortcut(for: other).modifiers == shortcut.modifiers
        }
        guard !isTaken else { return false }

        shortcuts[mode] = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: Self.shortcutDefaultsKey(for: mode))
        }
        onHotkeysChanged?()
        return true
    }

    func resetShortcuts() {
        shortcuts.removeAll()
        for mode in CaptureMode.allCases {
            UserDefaults.standard.removeObject(forKey: Self.shortcutDefaultsKey(for: mode))
        }
        onHotkeysChanged?()
    }

    private static func shortcutDefaultsKey(for mode: CaptureMode) -> String {
        "hotkey.\(mode.rawValue)"
    }

    // MARK: - Cross-cutting Methods

    func startCapture(mode: CaptureMode) {
        Task { @MainActor in
            await startCaptureAfterPermissionCheck(mode: mode)
        }
    }

    private func startCaptureAfterPermissionCheck(mode: CaptureMode) async {
        if await capture.hasUsableScreenCaptureAccess() {
            beginCapture(mode: mode)
            return
        }

        if !capture.requestScreenCaptureAccess() {
            capture.lastCaptureError = .permissionDenied
            appLogger.warning("Screen capture permission denied")
            capture.revealMainWindowForPermissionGuidance()
            return
        }

        beginCapture(mode: mode)
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

    private func updatePinWindow() {
        if showPinWindow, let pinnedImage {
            pinWindowController.show(image: pinnedImage, appState: self)
        } else {
            pinWindowController.hide()
        }
    }

    @MainActor
    private func renderAnnotatedImage() -> NSImage? {
        guard let image = capture.capturedImage else { return nil }
        guard #available(macOS 13.0, *) else { return nil }

        let exportSize = image.size
        guard exportSize.width > 0, exportSize.height > 0 else { return nil }

        let exportRect = CGRect(origin: .zero, size: exportSize)
        let scaledAnnotations = annotations.elements.map { $0.denormalized(in: exportRect) }

        let processedImage = applyImageEffects(to: image, annotations: scaledAnnotations)
        let visibleAnnotations = scaledAnnotations.filter { !$0.tool.isEffect }

        let content = AnnotationExportView(image: processedImage, annotations: visibleAnnotations)
            .frame(width: exportSize.width, height: exportSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = imageBackingScale(for: image)
        return renderer.nsImage
    }

    private func applyImageEffects(to image: NSImage, annotations: [AnnotationElement]) -> NSImage {
        annotations.reduce(image) { currentImage, element in
            guard let effectRect = element.effectRect, effectRect.width > 0, effectRect.height > 0 else {
                return currentImage
            }

            switch element.tool {
            case .blur:
                return currentImage.blur(amount: element.effectAmount, rect: effectRect) ?? currentImage
            case .pixelate:
                return currentImage.pixelate(amount: element.effectAmount, rect: effectRect) ?? currentImage
            default:
                return currentImage
            }
        }
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

        guard timerDuration > 0 else {
            capture.captureCountdown = 0
            Task { @MainActor in
                // Give the main window a moment to finish ordering out before capturing.
                try? await Task.sleep(for: .milliseconds(150))
                await performFullScreenCapture()
            }
            return
        }

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
                await self.performFullScreenCapture()
            }
        }
    }

    private func performFullScreenCapture() async {
        guard capture.isCapturing else { return }
        if let image = await capture.screenCapture.captureFullScreen() {
            handleCapturedImage(image)
        } else {
            capture.endCapture(showMainWindow: capture.wasMainWindowVisibleBeforeCapture)
        }
    }
}

// MARK: - ScreenshotHistoryManager

class ScreenshotHistoryManager: HistoryPersisting {
    /// Where new screenshots are saved: the user's real Downloads folder. Inside the sandbox,
    /// `FileManager`'s Downloads URL points into the app container, so build the path from the home directory.
    static var defaultSaveDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Downloads", isDirectory: true)
    }

    /// App-owned folder holding history.json and screenshots saved by earlier versions.
    static var defaultStoreDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("SnapClean/History", isDirectory: true)
    }

    private let historyKey = "screenshotHistory"
    private let historyFileName = "history.json"
    private let ioQueue = DispatchQueue(label: "com.snapclean.history-io", qos: .utility)
    let saveDirectory: URL
    let storeDirectory: URL
    private let historyFileURL: URL

    /// Only files inside the app-owned store may be deleted automatically; screenshots in
    /// the user's own folders (like Downloads) are never removed by history trimming or clearing.
    func isPathAllowed(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(storeDirectory.standardizedFileURL.path + "/")
    }

    init(
        saveDirectory: URL = ScreenshotHistoryManager.defaultSaveDirectory,
        storeDirectory: URL = ScreenshotHistoryManager.defaultStoreDirectory
    ) {
        self.saveDirectory = saveDirectory
        self.storeDirectory = storeDirectory
        historyFileURL = storeDirectory.appendingPathComponent(historyFileName)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
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

    func loadHistory() async -> [ScreenshotItem] {
        await withCheckedContinuation { continuation in
            ioQueue.async { [historyFileURL] in
                guard let data = try? Data(contentsOf: historyFileURL),
                      let history = try? JSONDecoder().decode([ScreenshotItem].self, from: data) else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: history.filter {
                    FileManager.default.fileExists(atPath: $0.filePath)
                })
            }
        }
    }

    func removeFiles(atPaths paths: [String]) {
        let uniquePaths = Array(Set(paths))
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            for path in uniquePaths where FileManager.default.fileExists(atPath: path) {
                guard self.isPathAllowed(path) else { continue }
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func trashFile(atPath path: String) {
        ioQueue.async {
            guard FileManager.default.fileExists(atPath: path) else { return }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            } catch {
                historyLogger.error("Failed to move screenshot to Trash: \(error.localizedDescription, privacy: .private)")
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
