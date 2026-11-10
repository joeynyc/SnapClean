import Foundation

enum CaptureMode: String, CaseIterable {
    case region
    case window
    case screen
}

enum CaptureError: LocalizedError, Equatable {
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
