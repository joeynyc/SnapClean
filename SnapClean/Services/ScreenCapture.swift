import Foundation
import Cocoa
import CoreGraphics
import ScreenCaptureKit

class ScreenCaptureService {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()

    func captureRegion(rect: CGRect) -> NSImage? {
        let captureRect = rect.integral
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: captureRect.size)
    }

    func captureFullScreen() -> NSImage? {
        guard let first = NSScreen.screens.first else { return nil }
        var unionRect = first.frame
        for screen in NSScreen.screens.dropFirst() {
            unionRect = unionRect.union(screen.frame)
        }
        guard let cgImage = CGWindowListCreateImage(
            unionRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: unionRect.size)
    }

    func captureWindow(at point: CGPoint) -> NSImage? {
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

    func captureWindowByID(_ windowID: CGWindowID, bounds: CGRect) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            bounds,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming]
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: bounds.size)
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

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
            try pngData.write(to: fileURL)
            return fileURL.path
        } catch {
            NSLog("SnapClean: Failed to save image: \(error.localizedDescription)")
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
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSColor.clear.set()
        draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    func pixelate(amount: CGFloat, rect: CGRect) -> NSImage? {
        guard let tiffData = self.tiffRepresentation,
              let ciImage = CIImage(data: tiffData),
              let filter = CIFilter(name: "CIPixellate") else {
            return nil
        }

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

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(composited, from: ciImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: self.size)
    }

    func blur(amount: CGFloat, rect: CGRect) -> NSImage? {
        guard let tiffData = self.tiffRepresentation,
              let ciImage = CIImage(data: tiffData),
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

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

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(composited, from: ciImage.extent) else { return nil }

        return NSImage(cgImage: cgImage, size: self.size)
    }

    func jpegThumbnailData(maxSize: NSSize, compression: CGFloat = 0.72) -> Data? {
        guard let resized = resizedToFit(maxSize: maxSize),
              let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
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
import AVFoundation

@available(macOS 14.0, *)
private final class StreamSingleFrameGrabber: NSObject, SCStreamOutput {
    private var firstSample: CMSampleBuffer?
    private let semaphore = DispatchSemaphore(value: 0)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        if firstSample == nil, CMSampleBufferIsValid(sampleBuffer) {
            firstSample = sampleBuffer
            semaphore.signal()
        }
    }

    func waitForFirstFrame(timeout: TimeInterval) -> CMSampleBuffer? {
        _ = semaphore.wait(timeout: .now() + timeout)
        return firstSample
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
