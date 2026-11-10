import SwiftUI
import AppKit
import ScreenCaptureKit
import os

let appLogger = Logger(subsystem: "com.snapclean.app", category: "app")

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
    /// File backing the pinned image: set when pinned from History or after the first save, nil for an unsaved editor image.
    private(set) var pinnedSourcePath: String?
    var isTransparentBackground = false {
        didSet { pinWindowController.setTransparentBackground(isTransparentBackground) }
    }

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
    /// Editor or floating thumbnail; only used while `showPreviewAfterCapture` is on.
    var afterCaptureAction: AfterCaptureAction = .openEditor {
        didSet { afterCaptureAction.store(in: .standard) }
    }
    /// The post-capture thumbnail shown when `afterCaptureAction` is `.floatingThumbnail`.
    let floatingThumbnail: FloatingThumbnailState
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
         historyManager: HistoryPersisting = ScreenshotHistoryManager(),
         thumbnailPresenter: FloatingThumbnailPresenting? = nil) {
        self.capture = CaptureState(screenCapture: screenCapture)
        self.annotations = AnnotationState()
        self.history = HistoryState(historyManager: historyManager)
        self.floatingThumbnail = FloatingThumbnailState(
            presenter: thumbnailPresenter ?? FloatingThumbnailWindowController()
        )

        // Load preferences from UserDefaults
        self.copyAfterCapture = UserDefaults.standard.bool(forKey: "copyAfterCapture")
        self.showPreviewAfterCapture = UserDefaults.standard.object(forKey: "showPreviewAfterCapture") == nil
            ? true : UserDefaults.standard.bool(forKey: "showPreviewAfterCapture")
        self.timerDuration = UserDefaults.standard.object(forKey: "timerDuration") == nil
            ? 3 : max(UserDefaults.standard.integer(forKey: "timerDuration"), 0)
        self.afterCaptureAction = AfterCaptureAction.load(from: .standard)
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
            self?.closePinnedImage()
        }
        pinWindowController.setTransparentBackground(isTransparentBackground)
        floatingThumbnail.actions = self
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
        if AfterCaptureOutcome(showPreview: showPreviewAfterCapture, action: afterCaptureAction) == .showFloatingThumbnail {
            showFloatingThumbnail(for: image)
            return
        }
        capture.capturedImage = image
        // Annotations are normalized, so the previous shot's would be drawn over this one.
        annotations.resetAnnotationState()
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
                capture.revealMainWindow()
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

    /// Ends a capture that produced no image. Pass `failure` to show it to the user; the main
    /// window is then revealed even if it was closed, so the alert has somewhere to appear.
    func endCaptureRestoringWindow(failure: CaptureError? = nil) {
        captureTimer?.invalidate()
        captureTimer = nil
        if let failure {
            capture.lastCaptureError = failure
            appLogger.error("Capture ended with error: \(failure.localizedDescription, privacy: .public)")
        }
        capture.endCapture(showMainWindow: failure != nil || capture.wasMainWindowVisibleBeforeCapture)
    }

    /// True while an editor save is encoding and writing; further save requests are ignored.
    private(set) var isSaving = false
    @ObservationIgnored private(set) var saveTask: Task<Void, Never>?

    /// Saves the annotated image. Rendering stays on the main actor; PNG encoding and effects run in the background.
    func saveAnnotation() {
        guard !isSaving else { return }
        isSaving = true
        saveTask = Task { @MainActor in
            await performSaveAnnotation()
            isSaving = false
        }
    }

    private func performSaveAnnotation() async {
        let sourceImage = capture.capturedImage
        guard let imageToSave = await currentEditableImageAsync() else { return }
        let folder = history.historyManager.saveDirectory
        guard let savedPath = await capture.screenCapture.saveImageInBackground(imageToSave, to: folder) else {
            capture.lastCaptureError = .saveFailed(folder.path)
            appLogger.error("Failed to save annotation")
            return
        }
        history.addToHistory(path: savedPath, image: imageToSave, limit: historyLimit)
        // A new capture may have replaced the editor's image while saving; leave that one alone.
        guard capture.capturedImage === sourceImage else { return }
        annotations.resetAnnotationState()
        capture.showAnnotationCanvas = false
    }

    /// Copies the annotated image, doing the PNG encoding off the main thread.
    func copyEditableImage() {
        Task { @MainActor in
            guard let image = await currentEditableImageAsync() else { return }
            await capture.screenCapture.copyToClipboardInBackground(image)
        }
    }

    func addToHistory(path: String, image: NSImage) {
        history.addToHistory(path: path, image: image, limit: historyLimit)
    }

    /// Pins an image. Pass `sourcePath` when the image was loaded from an existing file (e.g. History).
    func pinToScreen(_ image: NSImage, sourcePath: String? = nil) {
        pinnedImage = image
        pinnedSourcePath = sourcePath
        showPinWindow = true
    }

    func closePinnedImage() {
        showPinWindow = false
        pinnedImage = nil
        pinnedSourcePath = nil
    }

    /// Saves the pinned image once and records it in History. No-op if it already has a file.
    func savePinnedImage() {
        guard let image = pinnedImage, pinnedSourcePath == nil else { return }
        guard let path = capture.screenCapture.saveImage(image, to: history.historyManager.saveDirectory) else {
            capture.lastCaptureError = .saveFailed(history.historyManager.saveDirectory.path)
            capture.revealMainWindow()
            appLogger.error("Failed to save pinned image")
            return
        }
        pinnedSourcePath = path
        addToHistory(path: path, image: image)
    }

    /// Reveals the pinned image's file in Finder, saving it first if it has none.
    func revealPinnedImage() {
        if pinnedSourcePath == nil { savePinnedImage() }
        if let path = pinnedSourcePath {
            capture.screenCapture.openInFinder(path)
        }
    }

    /// The captured image with annotations applied. Commits any open text box first, so
    /// Copy, Save and Pin include text that is still being typed.
    func currentEditableImage() -> NSImage? {
        annotations.commitTextDraft()
        guard let plan = exportPlan() else { return capture.capturedImage }
        let base = ImageEffects.apply(plan.effects, to: plan.cgImage, pointSize: plan.size)
        return renderAnnotatedImage(plan, base: base) ?? capture.capturedImage
    }

    /// Like `currentEditableImage()`, but blur and pixelate run off the main thread.
    func currentEditableImageAsync() async -> NSImage? {
        annotations.commitTextDraft()
        guard let plan = exportPlan() else { return capture.capturedImage }
        let base = await Task.detached(priority: .userInitiated) {
            ImageEffects.apply(plan.effects, to: plan.cgImage, pointSize: plan.size)
        }.value
        return renderAnnotatedImage(plan, base: base) ?? capture.capturedImage
    }

    // MARK: - Private Helpers

    private func updatePinWindow() {
        if showPinWindow, let pinnedImage {
            pinWindowController.show(image: pinnedImage, appState: self)
        } else {
            pinWindowController.hide()
        }
    }

    private struct ExportPlan: @unchecked Sendable {
        let image: NSImage
        let cgImage: CGImage
        let size: CGSize
        let effects: [RegionEffect]
        let visibleAnnotations: [AnnotationElement]
    }

    private func exportPlan() -> ExportPlan? {
        guard let image = capture.capturedImage else { return nil }
        let exportSize = image.size
        guard exportSize.width > 0, exportSize.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let exportRect = CGRect(origin: .zero, size: exportSize)
        let scaled = annotations.elements.map { $0.denormalized(in: exportRect) }
        return ExportPlan(
            image: image,
            cgImage: cgImage,
            size: exportSize,
            effects: scaled.compactMap(\.regionEffect),
            visibleAnnotations: scaled.filter { !$0.tool.isEffect }
        )
    }

    /// Draws the visible annotations over the effect-processed base. ImageRenderer needs the main actor.
    private func renderAnnotatedImage(_ plan: ExportPlan, base: CGImage?) -> NSImage? {
        let processedImage = base.map { NSImage(cgImage: $0, size: plan.size) } ?? plan.image
        let content = AnnotationExportView(image: processedImage, annotations: plan.visibleAnnotations)
            .frame(width: plan.size.width, height: plan.size.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = imageBackingScale(for: plan.image)
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
            endCaptureRestoringWindow(failure: .captureFailed(.screen))
        }
    }
}
