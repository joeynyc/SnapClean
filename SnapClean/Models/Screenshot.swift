import SwiftUI
import Combine

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

    @Published var isTransparentBackground = false

    let screenCapture = ScreenCaptureService()
    let historyManager = ScreenshotHistoryManager()

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
            self?.startCapture(mode: mode)
        }

        NotificationCenter.default.addObserver(
            forName: .openHistory,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showHistory = true
        }
    }

    func startCapture(mode: CaptureMode) {
        currentCaptureMode = mode
        isCapturing = true
    }

    func handleCapturedImage(_ image: NSImage) {
        capturedImage = image
        isCapturing = false
        showAnnotationCanvas = true
    }

    func saveAnnotation() {
        guard let image = capturedImage else { return }
        let savedPath = screenCapture.saveImage(image)
        addToHistory(path: savedPath, image: image)
        resetAnnotationState()
        showAnnotationCanvas = false
    }

    func addToHistory(path: String, image: NSImage) {
        let thumbnail = image.resize(to: NSSize(width: 150, height: 100))?.tiffRepresentation
        let item = ScreenshotItem(date: Date(), filePath: path, thumbnail: thumbnail)
        screenshotHistory.insert(item, at: 0)
        if screenshotHistory.count > 50 {
            screenshotHistory.removeLast()
        }
        historyManager.saveHistory(screenshotHistory)
    }

    func loadHistory() {
        screenshotHistory = historyManager.loadHistory()
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
}

class ScreenshotHistoryManager {
    private let historyKey = "screenshotHistory"
    private let saveDirectory: URL

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
        loadHistory()
    }
}
