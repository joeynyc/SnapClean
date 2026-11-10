import Foundation
import Cocoa
import CoreGraphics
import ScreenCaptureKit
import os

// Shared CIContext for all filter operations (avoids expensive GPU/Metal setup on each call)
private let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])

private let captureLogger = Logger(subsystem: "com.snapclean.app", category: "capture")

/// A capturable window: its CGWindowID, a display name, and its frame in global display space.
typealias CapturableWindow = (id: CGWindowID, name: String, bounds: CGRect)

class ScreenCaptureService: ScreenCapturing {
    private let selfPID = ProcessInfo.processInfo.processIdentifier

    /// - Parameter rect: Region in global display space (top-left origin of the primary display, points);
    ///   see `CaptureGeometry` for the coordinate conventions.
    func captureRegion(rect: CGRect) async -> NSImage? {
        let captureRect = rect.integral
        guard captureRect.width > 0, captureRect.height > 0 else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let cgImage = try await captureRectWithScreenCaptureKit(captureRect, content: content) else { return nil }
            return NSImage(cgImage: cgImage, size: captureRect.size)
        } catch {
            captureLogger.error("Region capture failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func captureFullScreen() async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // SCDisplay.frame is already in global display space, unlike NSScreen.frame (Cocoa, bottom-left origin).
            guard let unionRect = CaptureGeometry.union(of: content.displays.map(\.frame))?.integral,
                  let cgImage = try await captureRectWithScreenCaptureKit(unionRect, content: content) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: unionRect.size)
        } catch {
            captureLogger.error("Full screen capture failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    func captureWindowByID(_ windowID: CGWindowID) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                captureLogger.error("No ScreenCaptureKit window found for ID \(windowID, privacy: .public)")
                return nil
            }

            let capture = try await captureWindowWithScreenCaptureKit(window, displays: content.displays)
            if capture.image.isLikelyBlank {
                captureLogger.error("Desktop-independent window capture returned a blank image; falling back to window frame capture")
                let fallbackRect = window.frame.integral
                guard let fallbackImage = try await captureRectWithScreenCaptureKit(fallbackRect, content: content) else {
                    return nil
                }
                return NSImage(cgImage: fallbackImage, size: fallbackRect.size)
            }
            return NSImage(cgImage: capture.image, size: capture.size)
        } catch {
            captureLogger.error("Window capture failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Captures `rect` (global display space) by grabbing the intersecting part of every display
    /// and stitching the slices into one bitmap.
    private func captureRectWithScreenCaptureKit(_ rect: CGRect, content: SCShareableContent) async throws -> CGImage? {
        let targetRect = rect.integral
        guard targetRect.width > 0, targetRect.height > 0 else { return nil }

        let displays = content.displays.filter { $0.frame.intersects(targetRect) }
        guard !displays.isEmpty else { return nil }

        // Exclude our own app so the capture overlay doesn't appear in screenshots
        let selfApps = content.applications.filter { $0.processID == selfPID }

        let outputScale = displays.map(displayScale(for:)).max() ?? 1.0
        let outputWidth = max(Int((targetRect.width * outputScale).rounded()), 1)
        let outputHeight = max(Int((targetRect.height * outputScale).rounded()), 1)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high

        var drewAnySlice = false

        for display in displays {
            let sliceRect = display.frame.intersection(targetRect)
            guard !sliceRect.isNull, sliceRect.width > 0, sliceRect.height > 0 else { continue }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: selfApps,
                exceptingWindows: []
            )
            let scale = displayScale(for: display)

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CaptureGeometry.sourceRect(forSlice: sliceRect, displayFrame: display.frame)
            configuration.width = max(Int((sliceRect.width * scale).rounded()), 1)
            configuration.height = max(Int((sliceRect.height * scale).rounded()), 1)
            configuration.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            // The bitmap context has a bottom-left origin; the slice offsets are top-left based.
            let destination = CaptureGeometry.stitchDestinationRect(
                forSlice: sliceRect,
                in: targetRect,
                outputScale: outputScale
            )
            context.draw(image, in: destination)
            drewAnySlice = true
        }

        guard drewAnySlice else { return nil }
        return context.makeImage()
    }

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

    private func displayScaleForWindow(_ window: SCWindow, displays: [SCDisplay]) -> CGFloat {
        // A window straddling displays gets the scale of the display holding most of it.
        let best = displays.max { lhs, rhs in
            CaptureGeometry.area(lhs.frame.intersection(window.frame))
                < CaptureGeometry.area(rhs.frame.intersection(window.frame))
        }
        guard let best, best.frame.intersects(window.frame) else { return 2.0 }
        return displayScale(for: best)
    }

    /// Pixels per point for a display. `SCDisplay.width`/`height` are documented in points, so dividing
    /// them by `frame.width` yields 1; read the backing scale from the current display mode instead.
    private func displayScale(for display: SCDisplay) -> CGFloat {
        if let mode = CGDisplayCopyDisplayMode(display.displayID), mode.width > 0 {
            let scale = CGFloat(mode.pixelWidth) / CGFloat(mode.width)
            if scale.isFinite, scale >= 1 {
                return scale
            }
        }
        guard display.frame.width > 0 else { return 2.0 }
        return max(CGFloat(display.width) / display.frame.width, 1.0)
    }

    /// Normal-layer, on-screen windows of other apps in global display space, ordered front to back
    /// (frontmost first) so the overlay can pick the topmost window under the pointer.
    func getWindowList() async -> [CapturableWindow] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let candidates: [CaptureGeometry.WindowCandidate] = content.windows.compactMap { window in
                guard let app = window.owningApplication, app.processID != selfPID else { return nil }

                let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = [app.applicationName, title].compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }.joined(separator: " - ")

                return CaptureGeometry.WindowCandidate(
                    id: window.windowID,
                    name: name.isEmpty ? "Window" : name,
                    frame: window.frame,
                    layer: window.windowLayer
                )
            }

            return CaptureGeometry
                .selectableWindowsFrontToBack(candidates, zOrder: Self.onScreenWindowZOrder())
                .map { (id: $0.id, name: $0.name, bounds: $0.frame) }
        } catch {
            captureLogger.error("Failed to load ScreenCaptureKit window list: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    /// The on-screen window stacking order. `SCShareableContent.windows` has no documented order, but
    /// `kCGWindowListOptionOnScreenOnly` is documented (CGWindow.h) as "ordered from front to back".
    private static func onScreenWindowZOrder() -> [CaptureGeometry.WindowOrderEntry] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber else { return nil }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return CaptureGeometry.WindowOrderEntry(id: CGWindowID(number.uint32Value), alpha: alpha)
        }
    }

    func saveImage(_ image: NSImage, to folder: URL? = nil) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return Self.writePNG(cgImage, to: folder)
    }

    /// Takes the CGImage on the calling actor, then encodes and writes the PNG on a background thread.
    func saveImageInBackground(_ image: NSImage, to folder: URL?) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return await Task.detached(priority: .userInitiated) { Self.writePNG(cgImage, to: folder) }.value
    }

    nonisolated private static func writePNG(_ cgImage: CGImage, to folder: URL?) -> String? {
        let saveFolder = folder ?? ScreenshotHistoryManager.defaultSaveDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let baseName = "SnapClean_\(formatter.string(from: Date()))"
        // Timestamps have one-second resolution; never overwrite an earlier save from the same second.
        var fileURL = saveFolder.appendingPathComponent("\(baseName).png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = saveFolder.appendingPathComponent("\(baseName) \(suffix).png")
            suffix += 1
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

    /// Encodes PNG off the main thread, then writes the pasteboard on the calling actor.
    func copyToClipboardInBackground(_ image: NSImage) async {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            copyToClipboard(image)
            return
        }
        let data = await Task.detached(priority: .userInitiated) {
            NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }.value
        guard let data else {
            copyToClipboard(image)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    func openInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

// MARK: - Capture Geometry

/// Pure coordinate math for capture. No AppKit screen lookups, so it can be unit-tested with synthetic layouts.
///
/// Coordinate spaces:
/// - **Cocoa** (`NSScreen.frame`, `NSWindow.frame`, `NSEvent.mouseLocation`): points, origin at the
///   bottom-left of the primary display (the one with the menu bar), y grows upward.
/// - **Display** (`CGDisplayBounds`, `SCDisplay.frame`, `SCWindow.frame`, CGWindowList bounds): points,
///   origin at the top-left of the primary display, y grows downward.
/// - **Overlay-local**: points relative to the top-left of one capture overlay window, which exactly
///   covers one screen, y grows downward. This is SwiftUI's `.global` space inside the overlay's hosting view.
enum CaptureGeometry {
    /// Converts a Cocoa rect to display space. `primaryScreenHeight` is the height of the primary display
    /// (the screen whose Cocoa frame origin is `.zero`).
    static func displayRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func displayPoint(fromCocoa point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Converts an overlay-local rect to display space, given the overlay's own frame in display space.
    static func displayRect(fromOverlayLocal rect: CGRect, overlayDisplayFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: overlayDisplayFrame.minX, dy: overlayDisplayFrame.minY)
    }

    static func overlayLocalRect(fromDisplay rect: CGRect, overlayDisplayFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -overlayDisplayFrame.minX, dy: -overlayDisplayFrame.minY)
    }

    static func overlayLocalPoint(fromDisplay point: CGPoint, overlayDisplayFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - overlayDisplayFrame.minX, y: point.y - overlayDisplayFrame.minY)
    }

    static func union(of rects: [CGRect]) -> CGRect? {
        let valid = rects.filter { !$0.isNull && !$0.isEmpty }
        guard let first = valid.first else { return nil }
        return valid.dropFirst().reduce(first) { $0.union($1) }
    }

    static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    /// `SCStreamConfiguration.sourceRect` for a slice: display-local points, top-left origin.
    static func sourceRect(forSlice slice: CGRect, displayFrame: CGRect) -> CGRect {
        slice.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    /// Where a slice (display space) of `target` (display space) is drawn in an output bitmap context
    /// whose origin is bottom-left, in pixels.
    static func stitchDestinationRect(forSlice slice: CGRect, in target: CGRect, outputScale: CGFloat) -> CGRect {
        CGRect(
            x: (slice.minX - target.minX) * outputScale,
            y: (target.maxY - slice.maxY) * outputScale,
            width: slice.width * outputScale,
            height: slice.height * outputScale
        )
    }

    // MARK: Window picker

    struct WindowCandidate: Equatable {
        let id: CGWindowID
        let name: String
        /// Display space.
        let frame: CGRect
        let layer: Int
    }

    struct WindowOrderEntry: Equatable {
        let id: CGWindowID
        let alpha: Double
    }

    /// Windows smaller than this (in points, either dimension) are not offered: they are almost always
    /// helper or status windows rather than something a user means to capture.
    static let minimumSelectableWindowSize: CGFloat = 40

    /// Keeps normal-layer (`layer == 0`) windows of a sensible size, drops fully transparent ones, and orders
    /// them front to back using the CGWindowList stacking order. Windows missing from `zOrder` go last,
    /// keeping their relative order; with an empty `zOrder` the input order is kept.
    static func selectableWindowsFrontToBack(
        _ candidates: [WindowCandidate],
        zOrder: [WindowOrderEntry],
        minimumSize: CGFloat = minimumSelectableWindowSize
    ) -> [WindowCandidate] {
        var rank: [CGWindowID: Int] = [:]
        var alpha: [CGWindowID: Double] = [:]
        for (index, entry) in zOrder.enumerated() where rank[entry.id] == nil {
            rank[entry.id] = index
            alpha[entry.id] = entry.alpha
        }

        let selectable = candidates.enumerated().filter { _, window in
            window.layer == 0
                && window.frame.width >= minimumSize
                && window.frame.height >= minimumSize
                && (alpha[window.id] ?? 1) > 0
        }

        return selectable.sorted { lhs, rhs in
            let lhsRank = rank[lhs.element.id] ?? Int.max
            let rhsRank = rank[rhs.element.id] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The windows (display space, front to back) that are visible on an overlay, converted to overlay-local
    /// coordinates and clipped to the overlay. Order is preserved.
    static func overlayWindows(
        _ windows: [CapturableWindow],
        overlayDisplayFrame: CGRect
    ) -> [CapturableWindow] {
        let overlayBounds = CGRect(origin: .zero, size: overlayDisplayFrame.size)
        return windows.compactMap { window in
            let local = overlayLocalRect(fromDisplay: window.bounds, overlayDisplayFrame: overlayDisplayFrame)
                .intersection(overlayBounds)
            guard !local.isNull, local.width > 0, local.height > 0 else { return nil }
            return (id: window.id, name: window.name, bounds: local)
        }
    }

    /// The frontmost window containing `point`, given windows ordered front to back.
    static func frontmostWindow(at point: CGPoint, in windows: [CapturableWindow]) -> CapturableWindow? {
        windows.first { $0.bounds.contains(point) }
    }

    // MARK: Image effects

    /// Blur radius (points) used for a given annotation `amount`. CIGaussianBlur's radius is roughly the
    /// standard deviation; at the editor's default amount (6) a 6 pt radius leaves body text legible,
    /// so the radius is doubled and never drops below 12 pt.
    static let blurRadiusMultiplier: CGFloat = 2
    static let minimumBlurRadiusPoints: CGFloat = 12

    /// CIGaussianBlur radius in pixels for an image with `pixelScale` pixels per point.
    static func blurRadiusPixels(amount: CGFloat, pixelScale: CGFloat) -> CGFloat {
        max(amount * blurRadiusMultiplier, minimumBlurRadiusPoints) * max(pixelScale, 1)
    }

    /// Converts a rect in image points (top-left origin) into an integral pixel rect with Core Image's
    /// bottom-left origin, expanded outward to whole pixels and clipped to the image.
    static func imagePixelRect(
        forTopLeftPointRect rect: CGRect,
        imagePointSize: CGSize,
        imagePixelSize: CGSize
    ) -> CGRect? {
        guard imagePointSize.width > 0, imagePointSize.height > 0 else { return nil }
        let scaleX = imagePixelSize.width / imagePointSize.width
        let scaleY = imagePixelSize.height / imagePointSize.height
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: (imagePointSize.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        .integral
        .intersection(CGRect(origin: .zero, size: imagePixelSize))
        guard !pixelRect.isNull, pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        return pixelRect
    }
}

private extension CGImage {
    var isLikelyBlank: Bool {
        let sampleWidth = min(width, 96)
        let sampleHeight = min(height, 96)
        guard sampleWidth > 0, sampleHeight > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return true
        }

        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return true
        }

        context.interpolationQuality = .none
        context.draw(self, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var hasNonBlackPixel = false
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = pixels[index]
            let green = pixels[index + 1]
            let blue = pixels[index + 2]
            let alpha = pixels[index + 3]
            if alpha > 0 && (red > 4 || green > 4 || blue > 4) {
                hasNonBlackPixel = true
                break
            }
        }

        return !hasNonBlackPixel
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

    /// Pixelates `rect` (image points, top-left origin). `amount` is the block size in points.
    func pixelate(amount: CGFloat, rect: CGRect) -> NSImage? {
        applyingSingleEffect(RegionEffect(kind: .pixelate, rect: rect, amount: amount))
    }

    /// Blurs `rect` (image points, top-left origin) strongly enough to redact text.
    /// The radius scales with the image's pixel density; see `CaptureGeometry.blurRadiusPixels`.
    func blur(amount: CGFloat, rect: CGRect) -> NSImage? {
        applyingSingleEffect(RegionEffect(kind: .blur, rect: rect, amount: amount))
    }

    private func applyingSingleEffect(_ effect: RegionEffect) -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let result = ImageEffects.apply([effect], to: cgImage, pointSize: size) else { return nil }
        return NSImage(cgImage: result, size: size)
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

// MARK: - Region effects

/// A blur or pixelate applied to a rectangle of an image.
struct RegionEffect: Sendable, Equatable {
    enum Kind: Sendable { case blur, pixelate }
    let kind: Kind
    /// Image points, top-left origin.
    let rect: CGRect
    let amount: CGFloat
}

/// Thread-safe Core Image effect pipeline shared by export and the editor's live preview,
/// so what the editor shows is what gets saved. Safe to call off the main thread.
enum ImageEffects {
    /// Applies `effects` in order and renders once. Returns nil when no effect applies (callers keep the original).
    /// Each effect only depends on pixels inside its region (cropped and edge-clamped), so the result
    /// never fades to transparent at the region or image edges.
    nonisolated static func apply(_ effects: [RegionEffect], to cgImage: CGImage, pointSize: CGSize) -> CGImage? {
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }
        let base = CIImage(cgImage: cgImage)
        let pixelScale = max(base.extent.width / pointSize.width, base.extent.height / pointSize.height)
        var current = base
        var applied = false

        for effect in effects {
            guard effect.rect.width > 0, effect.rect.height > 0,
                  let pixelRect = CaptureGeometry.imagePixelRect(
                    forTopLeftPointRect: effect.rect,
                    imagePointSize: pointSize,
                    imagePixelSize: base.extent.size
                  ) else { continue }

            let regionInput = current.cropped(to: pixelRect).clampedToExtent()
            let output: CIImage?
            switch effect.kind {
            case .pixelate:
                let filter = CIFilter(name: "CIPixellate")
                filter?.setValue(regionInput, forKey: kCIInputImageKey)
                filter?.setValue(max(effect.amount * pixelScale, 1), forKey: kCIInputScaleKey)
                // Anchor the block grid to the region instead of the filter's default (150, 150).
                filter?.setValue(CIVector(x: pixelRect.minX, y: pixelRect.minY), forKey: kCIInputCenterKey)
                output = filter?.outputImage
            case .blur:
                let filter = CIFilter(name: "CIGaussianBlur")
                filter?.setValue(regionInput, forKey: kCIInputImageKey)
                filter?.setValue(
                    CaptureGeometry.blurRadiusPixels(amount: effect.amount, pixelScale: pixelScale),
                    forKey: kCIInputRadiusKey
                )
                output = filter?.outputImage
            }
            guard let output else { continue }
            current = output.cropped(to: pixelRect).composited(over: current)
            applied = true
        }

        guard applied else { return nil }
        return sharedCIContext.createCGImage(current, from: base.extent)
    }
}

extension AnnotationElement {
    /// The effect this annotation applies, if it is a blur or pixelate with a usable rect.
    var regionEffect: RegionEffect? {
        guard let rect = effectRect, rect.width > 0, rect.height > 0 else { return nil }
        switch tool {
        case .blur: return RegionEffect(kind: .blur, rect: rect, amount: effectAmount)
        case .pixelate: return RegionEffect(kind: .pixelate, rect: rect, amount: effectAmount)
        default: return nil
        }
    }
}
