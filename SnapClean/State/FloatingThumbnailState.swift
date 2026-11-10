import AppKit

// MARK: - Dismiss schedule

/// When the floating thumbnail dismisses itself. Pure value type so the timing rules are testable.
///
/// The countdown runs only while the thumbnail is neither hovered nor held (a share picker is
/// open or a drag is in progress). Each time it stops being paused, the countdown restarts at the
/// full delay, so the thumbnail never vanishes the instant the pointer leaves it.
struct ThumbnailDismissSchedule: Equatable {
    static let defaultDelay: TimeInterval = 6

    let delay: TimeInterval
    private(set) var isHovered = false
    private(set) var holdCount = 0
    /// Nil while paused.
    private(set) var deadline: Date?

    init(delay: TimeInterval = defaultDelay, startingAt now: Date) {
        self.delay = delay
        self.deadline = now.addingTimeInterval(delay)
    }

    var isPaused: Bool { isHovered || holdCount > 0 }

    mutating func setHovered(_ hovering: Bool, at now: Date) {
        let wasPaused = isPaused
        isHovered = hovering
        update(wasPaused: wasPaused, now: now)
    }

    mutating func beginHold(at now: Date) {
        let wasPaused = isPaused
        holdCount += 1
        update(wasPaused: wasPaused, now: now)
    }

    mutating func endHold(at now: Date) {
        guard holdCount > 0 else { return }
        let wasPaused = isPaused
        holdCount -= 1
        update(wasPaused: wasPaused, now: now)
    }

    func isDue(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    private mutating func update(wasPaused: Bool, now: Date) {
        if isPaused {
            deadline = nil
        } else if wasPaused {
            deadline = now.addingTimeInterval(delay)
        }
    }
}

// MARK: - Endings

/// Why a floating thumbnail went away. Like macOS's screenshot thumbnail, the capture is saved
/// (once) unless the user closed it or took it into the editor, which saves on its own terms.
enum FloatingThumbnailEnding: Equatable {
    case timedOut
    /// A new capture took its place.
    case replaced
    case appTerminating
    case saved
    case pinned
    case closed
    case openedInEditor

    var savesCapture: Bool {
        switch self {
        case .timedOut, .replaced, .appTerminating, .saved, .pinned:
            return true
        case .closed, .openedInEditor:
            return false
        }
    }
}

// MARK: - Collaborators

/// What the thumbnail asks the app to do. `AppState` conforms; tests use a mock.
@MainActor
protocol FloatingThumbnailActions: AnyObject {
    /// Saves to the save directory and records the file in History. Returns the path, or nil on failure.
    func saveThumbnailCapture(_ image: NSImage) -> String?
    func openEditor(with image: NSImage)
    func pinToScreen(_ image: NSImage, sourcePath: String?)
    func copyImageToClipboard(_ image: NSImage)
}

/// Shows and hides the thumbnail's window. `FloatingThumbnailWindowController` conforms.
@MainActor
protocol FloatingThumbnailPresenting: AnyObject {
    /// `point` is in Cocoa screen coordinates; the thumbnail goes on the screen containing it.
    func show(_ state: FloatingThumbnailState, image: NSImage, near point: CGPoint?)
    func hide()
}

// MARK: - State

/// The floating post-capture thumbnail: which capture it shows, its auto-dismiss timer, and what
/// each of its buttons does. Holds no AppKit windows, so it can be tested without any.
@Observable @MainActor
final class FloatingThumbnailState {
    private(set) var image: NSImage?
    private(set) var isHovered = false

    @ObservationIgnored weak var actions: FloatingThumbnailActions?
    @ObservationIgnored private let presenter: FloatingThumbnailPresenting
    @ObservationIgnored private let delay: TimeInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let isMouseButtonDown: () -> Bool
    @ObservationIgnored private let exporter: TemporaryShareFile
    @ObservationIgnored private(set) var schedule: ThumbnailDismissSchedule?
    /// Changes with every capture, so a hold started for one thumbnail can't release another's.
    @ObservationIgnored private var session = UUID()
    @ObservationIgnored private var dismissTimer: Timer?
    @ObservationIgnored private var dragEndTimer: Timer?

    init(
        presenter: FloatingThumbnailPresenting,
        delay: TimeInterval = ThumbnailDismissSchedule.defaultDelay,
        exporter: TemporaryShareFile = TemporaryShareFile(),
        now: @escaping () -> Date = Date.init,
        isMouseButtonDown: @escaping () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    ) {
        self.presenter = presenter
        self.delay = delay
        self.exporter = exporter
        self.now = now
        self.isMouseButtonDown = isMouseButtonDown
    }

    var isShowing: Bool { image != nil }

    /// Shows `image`, first saving and replacing any thumbnail already on screen.
    func present(_ image: NSImage, near point: CGPoint?) {
        if isShowing {
            finish(.replaced)
        }
        session = UUID()
        self.image = image
        isHovered = false
        schedule = ThumbnailDismissSchedule(delay: delay, startingAt: now())
        presenter.show(self, image: image, near: point)
        scheduleDismissTimer()
    }

    func setHovered(_ hovering: Bool) {
        guard isShowing, hovering != isHovered else { return }
        isHovered = hovering
        schedule?.setHovered(hovering, at: now())
        scheduleDismissTimer()
    }

    /// Pauses auto-dismiss until `endHold` is called with the returned token.
    func beginHold() -> UUID {
        schedule?.beginHold(at: now())
        scheduleDismissTimer()
        return session
    }

    func endHold(_ token: UUID) {
        guard token == session else { return }
        schedule?.endHold(at: now())
        scheduleDismissTimer()
    }

    /// Dismisses (and saves) the thumbnail if its countdown has run out.
    func checkDeadline() {
        guard let schedule else { return }
        if schedule.isDue(at: now()) {
            finish(.timedOut)
        } else {
            scheduleDismissTimer()
        }
    }

    /// Removes the thumbnail, saving the capture if `ending` calls for it.
    func finish(_ ending: FloatingThumbnailEnding) {
        guard let image else { return }
        // Clear first so anything this triggers sees the thumbnail as gone.
        self.image = nil
        isHovered = false
        schedule = nil
        session = UUID()
        dismissTimer?.invalidate()
        dismissTimer = nil
        dragEndTimer?.invalidate()
        dragEndTimer = nil
        presenter.hide()

        let savedPath = ending.savesCapture ? actions?.saveThumbnailCapture(image) : nil
        switch ending {
        case .openedInEditor:
            actions?.openEditor(with: image)
        case .pinned:
            actions?.pinToScreen(image, sourcePath: savedPath)
        case .timedOut, .replaced, .appTerminating, .saved, .closed:
            break
        }
    }

    // MARK: Buttons

    func copy() {
        guard let image else { return }
        actions?.copyImageToClipboard(image)
    }

    func save() { finish(.saved) }
    func pin() { finish(.pinned) }
    func close() { finish(.closed) }
    func openEditor() { finish(.openedInEditor) }

    /// A temporary PNG of the capture for the share picker.
    func exportForSharing() -> URL? {
        guard let image else { return nil }
        return exporter.write(image)
    }

    /// Called when a drag out of the thumbnail starts. Holds the countdown until the mouse button
    /// is released (SwiftUI reports no drag end), then returns the drag payload.
    func beginDragOut() -> NSItemProvider {
        guard isShowing else { return NSItemProvider() }
        let token = beginHold()
        dragEndTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                if !self.isMouseButtonDown() {
                    timer.invalidate()
                    self.dragEndTimer = nil
                    self.endHold(token)
                }
            }
        }
        // .common so it also fires while the drag session tracks events.
        RunLoop.main.add(timer, forMode: .common)
        dragEndTimer = timer
        return ScreenshotDragItem.provider(for: image, exporter: exporter)
    }

    /// Test hook: runs the drag-end check now instead of waiting for the poll timer.
    func pollDragEnd() {
        dragEndTimer?.fire()
    }

    // MARK: Timer

    private func scheduleDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let deadline = schedule?.deadline else { return }
        // Relative to the injected clock, so a test clock can't schedule a timer in the past.
        let interval = max(deadline.timeIntervalSince(now()), 0)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkDeadline()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }
}
