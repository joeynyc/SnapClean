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
