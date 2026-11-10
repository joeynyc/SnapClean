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
    /// Inline JPEG thumbnail from older history.json files. Decoded only so it can be migrated to a
    /// file in `Thumbnails/`; never encoded. Current thumbnails live on disk (see `HistoryPersisting.thumbnailURL`).
    let legacyThumbnail: Data?

    init(id: UUID = UUID(), date: Date = Date(), filePath: String) {
        self.id = id
        self.date = date
        self.filePath = filePath
        self.legacyThumbnail = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, filePath
        case legacyThumbnail = "thumbnail"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        filePath = try container.decode(String.self, forKey: .filePath)
        legacyThumbnail = try container.decodeIfPresent(Data.self, forKey: .legacyThumbnail)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(filePath, forKey: .filePath)
    }
}
