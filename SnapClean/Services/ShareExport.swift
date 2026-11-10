import AppKit
import UniformTypeIdentifiers
import os

private let shareLogger = Logger(subsystem: "com.snapclean.app", category: "share")

/// File names for exported screenshots, matching the ones `ScreenCaptureService.saveImage` writes
/// ("SnapClean_2026-11-09_142501.png").
enum ScreenshotFileNaming {
    static let dateFormat = "yyyy-MM-dd_HHmmss"

    static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return "SnapClean_\(formatter.string(from: date))"
    }

    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        baseName(for: date, timeZone: timeZone) + ".png"
    }
}

/// Writes PNG copies of images into a temporary folder so they can be shared or dragged as files.
///
/// Each export goes into its own subfolder, so the file keeps the clean screenshot name even when
/// several are exported in the same second. Exports are kept for a day (a share target such as
/// AirDrop or Mail may read the file well after the picker closes) and pruned on the next export.
/// These files are never added to History; saving still goes through `ScreenCaptureService`.
struct TemporaryShareFile {
    static let folderName = "SnapCleanShare"
    static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    let root: URL
    let maxAge: TimeInterval

    init(
        root: URL = FileManager.default.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true),
        maxAge: TimeInterval = defaultMaxAge
    ) {
        self.root = root
        self.maxAge = maxAge
    }

    /// Writes `image` as a PNG and returns its URL, or nil if it couldn't be encoded or written.
    @discardableResult
    func write(_ image: NSImage, date: Date = Date()) -> URL? {
        guard let data = Self.pngData(for: image) else {
            shareLogger.error("Couldn't encode image for sharing")
            return nil
        }
        return write(pngData: data, date: date)
    }

    func write(pngData data: Data, date: Date = Date()) -> URL? {
        prune(now: date)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = folder.appendingPathComponent(ScreenshotFileNaming.fileName(for: date))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            shareLogger.error("Couldn't write share file: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Removes export folders older than `maxAge`.
    func prune(now: Date = Date()) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if now.timeIntervalSince(created) > maxAge {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

/// Drag payloads for screenshots: a file URL (Finder, Mail, Slack, Messages) plus the PNG data
/// for apps that only accept images.
enum ScreenshotDragItem {
    static func provider(forFileAt url: URL) -> NSItemProvider {
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    completion(try Data(contentsOf: url), nil)
                } catch {
                    completion(nil, error)
                }
            }
            return nil
        }
        return provider
    }

    /// Exports `image` to a temporary PNG and returns a provider for it. Returns an empty provider
    /// if the export fails, which makes the drag a no-op.
    static func provider(for image: NSImage?, exporter: TemporaryShareFile = TemporaryShareFile()) -> NSItemProvider {
        guard let image, let url = exporter.write(image) else { return NSItemProvider() }
        return provider(forFileAt: url)
    }
}
