import SwiftUI
import AppKit
import os

private let historyLogger = Logger(subsystem: "com.snapclean.app", category: "history")

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
    let thumbnailsDirectory: URL

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
        thumbnailsDirectory = storeDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        migrateFromLegacyUserDefaultsIfNeeded()
    }

    func saveHistory(_ history: [ScreenshotItem]) {
        ioQueue.async { [historyFileURL] in
            Self.writeHistory(history, to: historyFileURL)
        }
    }

    private static func writeHistory(_ history: [ScreenshotItem], to historyFileURL: URL) {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyFileURL, options: .atomic)
            // Set restrictive file permissions (owner-only read/write)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyFileURL.path)
        } catch {
            historyLogger.error("Failed to save history: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: Thumbnails

    func thumbnailURL(for id: UUID) -> URL {
        thumbnailsDirectory.appendingPathComponent("\(id.uuidString).jpg")
    }

    func saveThumbnail(_ data: Data, for id: UUID) async {
        await withCheckedContinuation { continuation in
            ioQueue.async { [self] in
                writeThumbnail(data, for: id)
                continuation.resume()
            }
        }
    }

    private func writeThumbnail(_ data: Data, for id: UUID) {
        do {
            try FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
            let url = thumbnailURL(for: id)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            historyLogger.error("Failed to save thumbnail: \(error.localizedDescription, privacy: .private)")
        }
    }

    func removeThumbnails(for ids: [UUID]) {
        ioQueue.async { [self] in
            for id in ids {
                try? FileManager.default.removeItem(at: thumbnailURL(for: id))
            }
        }
    }

    func loadHistory() async -> [ScreenshotItem] {
        await withCheckedContinuation { continuation in
            ioQueue.async { [self, historyFileURL] in
                guard let data = try? Data(contentsOf: historyFileURL),
                      let history = try? JSONDecoder().decode([ScreenshotItem].self, from: data) else {
                    continuation.resume(returning: [])
                    return
                }
                var kept = history.filter { FileManager.default.fileExists(atPath: $0.filePath) }
                // Older versions stored thumbnails inline in history.json: move them to files and drop them from the JSON.
                if history.contains(where: { $0.legacyThumbnail != nil }) {
                    for item in history {
                        if let thumbnail = item.legacyThumbnail { self.writeThumbnail(thumbnail, for: item.id) }
                    }
                    kept = kept.map { ScreenshotItem(id: $0.id, date: $0.date, filePath: $0.filePath) }
                    Self.writeHistory(kept, to: self.historyFileURL)
                }
                continuation.resume(returning: kept)
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
              (try? JSONDecoder().decode([ScreenshotItem].self, from: data)) != nil else {
            return
        }

        do {
            // Write the original bytes: inline thumbnails are moved to files by the next load.
            try data.write(to: historyFileURL, options: .atomic)
            UserDefaults.standard.removeObject(forKey: historyKey)
        } catch {
            historyLogger.error("Failed to migrate history store: \(error.localizedDescription, privacy: .private)")
        }
    }
}
