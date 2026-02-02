import Foundation
import Cocoa
import CoreGraphics

class ScreenCaptureService {
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()

    func captureRegion(rect: CGRect) -> NSImage? {
        let displayID = CGDirectDisplayID(CGMainDisplayID())
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else { return nil }
        return NSImage(cgImage: cgImage, size: rect.size)
    }

    func captureFullScreen() -> NSImage? {
        let screen = NSScreen.main
        guard let screenRect = screen?.frame else { return nil }
        let displayID = CGDirectDisplayID(CGMainDisplayID())
        guard let cgImage = CGDisplayCreateImage(displayID) else { return nil }
        return NSImage(cgImage: cgImage, size: screenRect.size)
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

    func saveImage(_ image: NSImage, to folder: URL? = nil) -> String {
        let saveFolder = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fileName = "SnapClean_\(dateFormatter.string(from: Date())).png"
        let fileURL = saveFolder.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return ""
        }

        try? pngData.write(to: fileURL)
        return fileURL.path
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func getImageSize(_ image: NSImage) -> NSSize {
        return image.size
    }

    func getPixelData(_ image: NSImage) -> [UInt8]? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let pixelsWide = bitmapImage.pixelsWide
        let pixelsHigh = bitmapImage.pixelsHigh
        var rawData = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)

        let context = CGContext(
            data: &rawData,
            width: pixelsWide,
            height: pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: 4 * pixelsWide,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let cgImage = bitmapImage.cgImage else { return nil }
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))

        return rawData
    }
}

extension NSImage {
    func resize(to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSColor.clear.set()
        newImage.draw(at: .zero, from: NSRect(origin: .zero, size: newSize), operation: .copy, fraction: 1.0)
        draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }

    func pixelate(amount: CGFloat, rect: CGRect) -> NSImage? {
        guard let ciImage = CIImage(data: self.tiffRepresentation ?? Data()),
              let filter = CIFilter(name: "CIPixellate") else {
            return nil
        }

        let scaleX = ciImage.extent.width / rect.width
        let scaleY = ciImage.extent.height / rect.height

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(amount * max(scaleX, scaleY), forKey: kCIInputScaleKey)

        guard let outputCIImage = filter.outputImage,
              let cgImage = CIContext(options: nil).createCGImage(outputCIImage, from: ciImage.extent) else {
            return nil
        }

        let result = NSImage(cgImage: cgImage, size: self.size)

        let finalImage = NSImage(size: self.size)
        finalImage.lockFocus()
        self.draw(at: .zero, from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        result.draw(at: rect.origin, from: rect, operation: .destinationIn, fraction: 1.0)
        finalImage.unlockFocus()

        return finalImage
    }

    func blur(amount: CGFloat, rect: CGRect) -> NSImage? {
        guard let ciImage = CIImage(data: self.tiffRepresentation ?? Data()),
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(amount, forKey: kCIInputRadiusKey)

        guard let outputCIImage = filter.outputImage,
              let cgImage = CIContext(options: nil).createCGImage(outputCIImage, from: ciImage.extent) else {
            return nil
        }

        let result = NSImage(cgImage: cgImage, size: self.size)

        let finalImage = NSImage(size: self.size)
        finalImage.lockFocus()
        self.draw(at: .zero, from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        result.draw(at: rect.origin, from: rect, operation: .destinationIn, fraction: 1.0)
        finalImage.unlockFocus()

        return finalImage
    }
}
