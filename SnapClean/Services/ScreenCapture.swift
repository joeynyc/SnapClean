import Foundation
import Cocoa
import CoreGraphics
import ScreenCaptureKit
import os

// Shared CIContext for all filter operations (avoids expensive GPU/Metal setup on each call)
private let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

private let captureLogger = Logger(subsystem: "com.snapclean.app", category: "capture")

class ScreenCaptureService: ScreenCapturing {
    private final class CaptureBox<T>: @unchecked Sendable {
        var value: T?
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()

    func captureRegion(rect: CGRect) -> NSImage? {
        let captureRect = rect.integral
        guard captureRect.width > 0, captureRect.height > 0 else { return nil }

        let cgImage: CGImage?
        if #available(macOS 14.0, *) {
            cgImage = performSyncCapture {
                try await self.captureRectWithScreenCaptureKit(captureRect)
            }
        } else {
            cgImage = CGWindowListCreateImage(
                captureRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
        }

        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: captureRect.size)
    }

    func captureFullScreen() -> NSImage? {
        guard let first = NSScreen.screens.first else { return nil }
        var unionRect = first.frame
        for screen in NSScreen.screens.dropFirst() {
            unionRect = unionRect.union(screen.frame)
        }
        let captureRect = unionRect

        let cgImage: CGImage?
        if #available(macOS 14.0, *) {
            cgImage = performSyncCapture {
                try await self.captureRectWithScreenCaptureKit(captureRect)
            }
        } else {
            cgImage = CGWindowListCreateImage(
                captureRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            )
        }

        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: captureRect.size)
    }

    func captureWindow(at point: CGPoint) -> NSImage? {
        if #available(macOS 14.0, *) {
            guard let result: (image: CGImage, size: CGSize) = performSyncCapture({
                try await self.captureWindowAtPointWithScreenCaptureKit(point)
            }) else { return nil }
            return NSImage(cgImage: result.image, size: result.size)
        } else {
            let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, CGWindowID(0))
            guard let windowList = windowList else { return nil }

            let windows = windowList as? [[String: Any]] ?? []
            for window in windows {
                if let bounds = window[kCGWindowBounds as String] as? [String: Any],
                   let windowID = window[kCGWindowNumber as String] as? Int {
                    let rect = CGRect(
                        x: bounds["X"] as? CGFloat ?? 0,
                        y: bounds["Y"] as? CGFloat ?? 0,
                        width: bounds["Width"] as? CGFloat ?? 0,
                        height: bounds["Height"] as? CGFloat ?? 0
                    )
                    if rect.contains(point) {
                        if let cgImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, CGWindowID(windowID), []) {
                            return NSImage(cgImage: cgImage, size: rect.size)
                        }
                    }
                }
            }
            return nil
        }
    }

    func captureWindowByID(_ windowID: CGWindowID, bounds: CGRect) -> NSImage? {
        let cgImage: CGImage?
        if #available(macOS 14.0, *) {
            guard let result: (image: CGImage, size: CGSize) = performSyncCapture({
                try await self.captureWindowByIDWithScreenCaptureKit(windowID)
            }) else { return nil }
            return NSImage(cgImage: result.image, size: result.size)
        } else {
            cgImage = CGWindowListCreateImage(
                bounds,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming]
            )
            guard let cgImage else { return nil }
            return NSImage(cgImage: cgImage, size: bounds.size)
        }
    }

    private func performSyncCapture<T>(
        _ operation: @escaping @Sendable () async throws -> T?
    ) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = CaptureBox<T>()

        Task.detached(priority: .userInitiated) {
            defer { semaphore.signal() }
            do {
                box.value = try await operation()
            } catch {
                captureLogger.error("ScreenCaptureKit capture failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        semaphore.wait()
        return box.value
    }

    @available(macOS 14.0, *)
    private func captureRectWithScreenCaptureKit(_ rect: CGRect) async throws -> CGImage? {
        let targetRect = rect.integral
        guard targetRect.width > 0, targetRect.height > 0 else { return nil }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displays = content.displays.filter { $0.frame.intersects(targetRect) }
        guard !displays.isEmpty else { return nil }

        let composite = NSImage(size: targetRect.size)
        composite.lockFocus()
        defer { composite.unlockFocus() }

        var drewAnySlice = false

        for display in displays {
            let sliceRect = display.frame.intersection(targetRect)
            guard !sliceRect.isNull, sliceRect.width > 0, sliceRect.height > 0 else { continue }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scale = displayScale(for: display)

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(
                x: sliceRect.minX - display.frame.minX,
                y: sliceRect.minY - display.frame.minY,
                width: sliceRect.width,
                height: sliceRect.height
            )
            configuration.width = max(Int((sliceRect.width * scale).rounded()), 1)
            configuration.height = max(Int((sliceRect.height * scale).rounded()), 1)
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            let renderedSlice = NSImage(cgImage: image, size: sliceRect.size)
            let destination = CGRect(
                x: sliceRect.minX - targetRect.minX,
                y: sliceRect.minY - targetRect.minY,
                width: sliceRect.width,
                height: sliceRect.height
            )
            renderedSlice.draw(in: destination)
            drewAnySlice = true
        }

        guard drewAnySlice else { return nil }
        return composite.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    @available(macOS 14.0, *)
    private func captureWindowAtPointWithScreenCaptureKit(_ point: CGPoint) async throws -> (image: CGImage, size: CGSize)? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let selfPID = ProcessInfo.processInfo.processIdentifier

        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID != selfPID &&
            $0.frame.contains(point) &&
            $0.frame.width > 1 &&
            $0.frame.height > 1
        }) else { return nil }

        return try await captureWindowWithScreenCaptureKit(window, displays: content.displays)
    }

    @available(macOS 14.0, *)
    private func captureWindowByIDWithScreenCaptureKit(_ windowID: CGWindowID) async throws -> (image: CGImage, size: CGSize)? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        return try await captureWindowWithScreenCaptureKit(window, displays: content.displays)
    }

    @available(macOS 14.0, *)
    private func captureWindowWithScreenCaptureKit(
        _ window: SCWindow,
        displays: [SCDisplay]
    ) async throws -> (image: CGImage, size: CGSize) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = displayScaleForWindow(window, displays: displays)

        let configuration = SCStreamConfiguration()
        configuration.width = max(Int((window.frame.width * scale).rounded()), 1)
        configuration.height = max(Int((window.frame.height * scale).rounded()), 1)
        configuration.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return (image: image, size: window.frame.size)
    }

    @available(macOS 14.0, *)
    private func displayScaleForWindow(_ window: SCWindow, displays: [SCDisplay]) -> CGFloat {
        guard let display = displays.first(where: { $0.frame.intersects(window.frame) }) else { return 2.0 }
        return displayScale(for: display)
    }

    @available(macOS 14.0, *)
    private func displayScale(for display: SCDisplay) -> CGFloat {
        guard display.frame.width > 0 else { return 2.0 }
        return max(CGFloat(display.width) / display.frame.width, 1.0)
    }

    func getWindowList() -> [(id: CGWindowID, name: String, bounds: CGRect)] {
        let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, CGWindowID(0))
        guard let windowList = windowList else { return [] }

        let windows = windowList as? [[String: Any]] ?? []
        var result: [(id: CGWindowID, name: String, bounds: CGRect)] = []

        for window in windows {
            if let bounds = window[kCGWindowBounds as String] as? [String: Any],
               let windowID = window[kCGWindowNumber as String] as? Int,
               let name = window[kCGWindowName as String] as? String {

                let rect = CGRect(
                    x: bounds["X"] as? CGFloat ?? 0,
                    y: bounds["Y"] as? CGFloat ?? 0,
                    width: bounds["Width"] as? CGFloat ?? 0,
                    height: bounds["Height"] as? CGFloat ?? 0
                )
                result.append((id: CGWindowID(windowID), name: name, bounds: rect))
            }
        }

        return result
    }

    func saveImage(_ image: NSImage, to folder: URL? = nil) -> String? {
        let saveFolder = folder ?? ScreenshotHistoryManager.defaultSaveDirectory
        let fileName = "SnapClean_\(dateFormatter.string(from: Date())).png"
        let fileURL = saveFolder.appendingPathComponent(fileName)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
            try pngData.write(to: fileURL)
            // Set restrictive file permissions (owner-only read/write)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return fileURL.path
        } catch {
            captureLogger.error("Failed to save image: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

extension NSImage {
    func resize(to newSize: NSSize) -> NSImage? {
        guard newSize.width > 0, newSize.height > 0 else { return nil }
        return NSImage(size: newSize, flipped: false) { rect in
            self.draw(in: rect, from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
            return true
        }
    }

    func pixelate(amount: CGFloat, rect: CGRect) -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIPixellate") else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let scaleX = ciImage.extent.width / self.size.width
        let scaleY = ciImage.extent.height / self.size.height

        let ciRect = CGRect(
            x: rect.origin.x * scaleX,
            y: (self.size.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(amount * max(scaleX, scaleY), forKey: kCIInputScaleKey)

        guard let outputCIImage = filter.outputImage else { return nil }

        let croppedOutput = outputCIImage.cropped(to: ciRect)
        let composited = croppedOutput.composited(over: ciImage)

        guard let resultCGImage = sharedCIContext.createCGImage(composited, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: resultCGImage, size: self.size)
    }

    func blur(amount: CGFloat, rect: CGRect) -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let scaleX = ciImage.extent.width / self.size.width
        let scaleY = ciImage.extent.height / self.size.height

        let ciRect = CGRect(
            x: rect.origin.x * scaleX,
            y: (self.size.height - rect.origin.y - rect.height) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(amount, forKey: kCIInputRadiusKey)

        guard let outputCIImage = filter.outputImage else { return nil }

        let croppedOutput = outputCIImage.cropped(to: ciRect)
        let composited = croppedOutput.composited(over: ciImage)

        guard let resultCGImage = sharedCIContext.createCGImage(composited, from: ciImage.extent) else {
            return nil
        }

        return NSImage(cgImage: resultCGImage, size: self.size)
    }

    func jpegThumbnailData(maxSize: NSSize, compression: CGFloat = 0.72) -> Data? {
        guard let resized = resizedToFit(maxSize: maxSize),
              let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: min(max(compression, 0.1), 1.0)]
        )
    }

    private func resizedToFit(maxSize: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        return resize(to: target)
    }
}
