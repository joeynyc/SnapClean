import XCTest
import AppKit
@testable import SnapClean

/// Synthetic multi-display layouts. The primary display is 1440×900 at the origin in both spaces.
/// Cocoa frames are bottom-left origin (y up); display frames are top-left origin (y down).
private enum Layout {
    static let primaryHeight: CGFloat = 900
    static let primaryCocoa = CGRect(x: 0, y: 0, width: 1440, height: 900)
    static let primaryDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)

    /// 2560×1440 to the right, top edges aligned.
    static let rightCocoa = CGRect(x: 1440, y: -540, width: 2560, height: 1440)
    static let rightDisplay = CGRect(x: 1440, y: 0, width: 2560, height: 1440)

    /// 1920×1080 to the left (negative x), bottom edges aligned.
    static let leftCocoa = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    static let leftDisplay = CGRect(x: -1920, y: -180, width: 1920, height: 1080)

    /// 1920×1080 above, offset left by 240.
    static let aboveCocoa = CGRect(x: -240, y: 900, width: 1920, height: 1080)
    static let aboveDisplay = CGRect(x: -240, y: -1080, width: 1920, height: 1080)

    /// 1280×800 below, offset right by 80.
    static let belowCocoa = CGRect(x: 80, y: -800, width: 1280, height: 800)
    static let belowDisplay = CGRect(x: 80, y: 900, width: 1280, height: 800)
}

final class CaptureGeometryTests: XCTestCase {
    // MARK: Cocoa -> display space

    func testCocoaToDisplayRectForEachArrangement() {
        let cases: [(CGRect, CGRect)] = [
            (Layout.primaryCocoa, Layout.primaryDisplay),
            (Layout.rightCocoa, Layout.rightDisplay),
            (Layout.leftCocoa, Layout.leftDisplay),
            (Layout.aboveCocoa, Layout.aboveDisplay),
            (Layout.belowCocoa, Layout.belowDisplay)
        ]
        for (cocoa, expected) in cases {
            XCTAssertEqual(
                CaptureGeometry.displayRect(fromCocoa: cocoa, primaryScreenHeight: Layout.primaryHeight),
                expected,
                "Cocoa \(cocoa)"
            )
        }
    }

    func testCocoaToDisplayPoint() {
        // Top-left corner of the primary display.
        XCTAssertEqual(
            CaptureGeometry.displayPoint(fromCocoa: CGPoint(x: 0, y: 900), primaryScreenHeight: 900),
            CGPoint(x: 0, y: 0)
        )
        // A point on the display below the primary.
        XCTAssertEqual(
            CaptureGeometry.displayPoint(fromCocoa: CGPoint(x: 100, y: -100), primaryScreenHeight: 900),
            CGPoint(x: 100, y: 1000)
        )
    }

    // MARK: Overlay-local <-> display space

    func testOverlaySelectionMapsToTheOverlaysOwnDisplay() {
        let selection = CGRect(x: 100, y: 50, width: 200, height: 120)
        let cases: [(CGRect, CGRect)] = [
            (Layout.primaryDisplay, CGRect(x: 100, y: 50, width: 200, height: 120)),
            (Layout.rightDisplay, CGRect(x: 1540, y: 50, width: 200, height: 120)),
            (Layout.leftDisplay, CGRect(x: -1820, y: -130, width: 200, height: 120)),
            (Layout.aboveDisplay, CGRect(x: -140, y: -1030, width: 200, height: 120)),
            (Layout.belowDisplay, CGRect(x: 180, y: 950, width: 200, height: 120))
        ]
        for (overlayFrame, expected) in cases {
            let global = CaptureGeometry.displayRect(fromOverlayLocal: selection, overlayDisplayFrame: overlayFrame)
            XCTAssertEqual(global, expected, "overlay \(overlayFrame)")
            XCTAssertTrue(overlayFrame.contains(global), "selection should land on its own display")
            XCTAssertEqual(
                CaptureGeometry.overlayLocalRect(fromDisplay: global, overlayDisplayFrame: overlayFrame),
                selection
            )
        }
    }

    func testOverlayFrameFromCocoaWindowFrameMapsOriginToScreenTopLeft() {
        // The overlay controller derives each overlay's display frame from its Cocoa window frame.
        let overlay = CaptureGeometry.displayRect(fromCocoa: Layout.belowCocoa, primaryScreenHeight: Layout.primaryHeight)
        let topLeft = CaptureGeometry.displayRect(
            fromOverlayLocal: CGRect(x: 0, y: 0, width: 1, height: 1),
            overlayDisplayFrame: overlay
        )
        XCTAssertEqual(topLeft.origin, CGPoint(x: 80, y: 900))
    }

    func testMouseLocationSeedMapsToOverlayLocalPoint() {
        // Cocoa mouse at (1500, 800) is 60pt right of the right display's left edge, 100pt below the top.
        let display = CaptureGeometry.displayPoint(fromCocoa: CGPoint(x: 1500, y: 800), primaryScreenHeight: 900)
        let local = CaptureGeometry.overlayLocalPoint(fromDisplay: display, overlayDisplayFrame: Layout.rightDisplay)
        XCTAssertEqual(local, CGPoint(x: 60, y: 100))
    }

    // MARK: Full-screen union

    func testUnionOfDisplayFrames() {
        let union = CaptureGeometry.union(of: [
            Layout.primaryDisplay, Layout.rightDisplay, Layout.leftDisplay, Layout.aboveDisplay, Layout.belowDisplay
        ])
        XCTAssertEqual(union, CGRect(x: -1920, y: -1080, width: 1920 + 1440 + 2560, height: 1080 + 900 + 800))
        XCTAssertNil(CaptureGeometry.union(of: []))
    }

    func testUnionUsesDisplayFramesNotCocoaFrames() {
        // Primary + display below. In Cocoa the union spans y -800...900; in display space 0...1700.
        let union = CaptureGeometry.union(of: [Layout.primaryDisplay, Layout.belowDisplay])
        XCTAssertEqual(union, CGRect(x: 0, y: 0, width: 1440, height: 1700))
    }

    // MARK: Slices and stitching

    func testSourceRectIsDisplayLocal() {
        let slice = CGRect(x: -500, y: 0, width: 300, height: 200)
        XCTAssertEqual(
            CaptureGeometry.sourceRect(forSlice: slice, displayFrame: Layout.leftDisplay),
            CGRect(x: 1420, y: 180, width: 300, height: 200)
        )
        XCTAssertEqual(
            CaptureGeometry.sourceRect(forSlice: CGRect(x: 100, y: 1000, width: 50, height: 50), displayFrame: Layout.belowDisplay),
            CGRect(x: 20, y: 100, width: 50, height: 50)
        )
    }

    func testStitchingPlacesUpperSliceAtTopOfBottomLeftContext() {
        // A selection spanning the primary display and the display below it.
        let target = CGRect(x: 100, y: 800, width: 400, height: 200)
        let upper = Layout.primaryDisplay.intersection(target)   // y 800...900
        let lower = Layout.belowDisplay.intersection(target)     // y 900...1000

        XCTAssertEqual(
            CaptureGeometry.stitchDestinationRect(forSlice: upper, in: target, outputScale: 2),
            CGRect(x: 0, y: 200, width: 800, height: 200)
        )
        XCTAssertEqual(
            CaptureGeometry.stitchDestinationRect(forSlice: lower, in: target, outputScale: 2),
            CGRect(x: 0, y: 0, width: 800, height: 200)
        )
    }

    func testStitchingAboveAndLeftDisplays() {
        // Above: target spans the above display (y < 0) and the primary.
        let vertical = CGRect(x: 0, y: -100, width: 100, height: 300)
        XCTAssertEqual(
            CaptureGeometry.stitchDestinationRect(forSlice: Layout.aboveDisplay.intersection(vertical), in: vertical, outputScale: 1),
            CGRect(x: 0, y: 200, width: 100, height: 100)
        )
        XCTAssertEqual(
            CaptureGeometry.stitchDestinationRect(forSlice: Layout.primaryDisplay.intersection(vertical), in: vertical, outputScale: 1),
            CGRect(x: 0, y: 0, width: 100, height: 200)
        )

        // Left: target spans the left display (negative x, y offset -180) and the primary.
        let horizontal = CGRect(x: -100, y: -50, width: 300, height: 150)
        let leftSlice = Layout.leftDisplay.intersection(horizontal)       // x -100...0, y -50...100
        let primarySlice = Layout.primaryDisplay.intersection(horizontal) // x 0...200, y 0...100
        XCTAssertEqual(
            CaptureGeometry.stitchDestinationRect(forSlice: leftSlice, in: horizontal, outputScale: 2),
            CGRect(x: 0, y: 0, width: 200, height: 300)
        )
        XCTAssertEqual(
            CaptureGeometry.stitchDestinationRect(forSlice: primarySlice, in: horizontal, outputScale: 2),
            CGRect(x: 200, y: 0, width: 400, height: 200)
        )
    }

    func testStitchedBitmapHasUpperDisplayOnTop() throws {
        let target = CGRect(x: 100, y: 800, width: 400, height: 200)
        let upper = Layout.primaryDisplay.intersection(target)
        let lower = Layout.belowDisplay.intersection(target)
        let scale: CGFloat = 1

        let context = try XCTUnwrap(TestBitmap.makeContext(width: 400, height: 200))
        context.draw(try XCTUnwrap(TestBitmap.solid(red: 255, green: 0, blue: 0)),
                     in: CaptureGeometry.stitchDestinationRect(forSlice: upper, in: target, outputScale: scale))
        context.draw(try XCTUnwrap(TestBitmap.solid(red: 0, green: 0, blue: 255)),
                     in: CaptureGeometry.stitchDestinationRect(forSlice: lower, in: target, outputScale: scale))
        let image = try XCTUnwrap(context.makeImage())
        let pixels = try XCTUnwrap(TestBitmap.rgba(image))

        // Row 0 of the image is its top row.
        XCTAssertEqual(pixels.pixel(x: 10, y: 10).r, 255)
        XCTAssertEqual(pixels.pixel(x: 10, y: 10).b, 0)
        XCTAssertEqual(pixels.pixel(x: 10, y: 190).r, 0)
        XCTAssertEqual(pixels.pixel(x: 10, y: 190).b, 255)
    }

    // MARK: Window picker

    private func candidate(_ id: CGWindowID, _ frame: CGRect, layer: Int = 0) -> CaptureGeometry.WindowCandidate {
        CaptureGeometry.WindowCandidate(id: id, name: "w\(id)", frame: frame, layer: layer)
    }

    func testSelectableWindowsFiltersLayersSizeAndTransparentWindows() {
        let candidates = [
            candidate(1, CGRect(x: 0, y: 0, width: 800, height: 600)),
            candidate(2, CGRect(x: 0, y: 0, width: 1440, height: 24), layer: 24),   // menu bar
            candidate(3, CGRect(x: 0, y: 820, width: 1440, height: 80), layer: 20),  // Dock
            candidate(4, CGRect(x: 1200, y: 0, width: 30, height: 24)),              // status-item sized
            candidate(5, CGRect(x: 0, y: 0, width: 1440, height: 900)),              // invisible (alpha 0)
            candidate(6, CGRect(x: 10, y: 10, width: 40, height: 40))
        ]
        let zOrder = [1, 2, 3, 4, 5, 6].map { CaptureGeometry.WindowOrderEntry(id: $0, alpha: $0 == 5 ? 0 : 1) }
        let result = CaptureGeometry.selectableWindowsFrontToBack(candidates, zOrder: zOrder)
        XCTAssertEqual(result.map(\.id), [1, 6])
    }

    func testSelectableWindowsAreOrderedByCGWindowListFrontToBack() {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 500)
        let candidates = [candidate(10, frame), candidate(20, frame), candidate(30, frame), candidate(40, frame)]
        let zOrder = [30, 99, 10, 20].map { CaptureGeometry.WindowOrderEntry(id: $0, alpha: 1) }
        let result = CaptureGeometry.selectableWindowsFrontToBack(candidates, zOrder: zOrder)
        // 40 is missing from the stacking order, so it goes last.
        XCTAssertEqual(result.map(\.id), [30, 10, 20, 40])

        XCTAssertEqual(
            CaptureGeometry.selectableWindowsFrontToBack(candidates, zOrder: []).map(\.id),
            [10, 20, 30, 40]
        )
    }

    func testOverlayWindowsOnlyIncludesWindowsOnThatScreenInLocalCoordinates() {
        let windows: [CapturableWindow] = [
            (id: 1, name: "front, straddles primary/right", bounds: CGRect(x: 1240, y: 100, width: 400, height: 300)),
            (id: 2, name: "primary only", bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            (id: 3, name: "right only", bounds: CGRect(x: 2000, y: 500, width: 600, height: 400))
        ]

        let onRight = CaptureGeometry.overlayWindows(windows, overlayDisplayFrame: Layout.rightDisplay)
        XCTAssertEqual(onRight.map(\.id), [1, 3])
        XCTAssertEqual(onRight[0].bounds, CGRect(x: 0, y: 100, width: 200, height: 300))
        XCTAssertEqual(onRight[1].bounds, CGRect(x: 560, y: 500, width: 600, height: 400))

        let onPrimary = CaptureGeometry.overlayWindows(windows, overlayDisplayFrame: Layout.primaryDisplay)
        XCTAssertEqual(onPrimary.map(\.id), [1, 2])
        XCTAssertEqual(onPrimary[0].bounds, CGRect(x: 1240, y: 100, width: 200, height: 300))

        let onLeft = CaptureGeometry.overlayWindows(
            [(id: 4, name: "left", bounds: CGRect(x: -1000, y: -100, width: 300, height: 200))],
            overlayDisplayFrame: Layout.leftDisplay
        )
        XCTAssertEqual(onLeft.first?.bounds, CGRect(x: 920, y: 80, width: 300, height: 200))

        let onAbove = CaptureGeometry.overlayWindows(windows, overlayDisplayFrame: Layout.aboveDisplay)
        XCTAssertTrue(onAbove.isEmpty)
    }

    func testFrontmostWindowWinsWhereWindowsOverlap() {
        let windows: [CapturableWindow] = [
            (id: 1, name: "front", bounds: CGRect(x: 100, y: 100, width: 200, height: 200)),
            (id: 2, name: "back", bounds: CGRect(x: 0, y: 0, width: 600, height: 600))
        ]
        XCTAssertEqual(CaptureGeometry.frontmostWindow(at: CGPoint(x: 150, y: 150), in: windows)?.id, 1)
        XCTAssertEqual(CaptureGeometry.frontmostWindow(at: CGPoint(x: 50, y: 50), in: windows)?.id, 2)
        XCTAssertNil(CaptureGeometry.frontmostWindow(at: CGPoint(x: 700, y: 50), in: windows))
    }

    // MARK: Effects geometry

    func testBlurRadiusScalesWithPixelDensityAndHasARedactionMinimum() {
        XCTAssertEqual(CaptureGeometry.blurRadiusPixels(amount: 6, pixelScale: 1), 12)
        XCTAssertEqual(CaptureGeometry.blurRadiusPixels(amount: 6, pixelScale: 2), 24)
        XCTAssertEqual(CaptureGeometry.blurRadiusPixels(amount: 10, pixelScale: 2), 40)
        XCTAssertEqual(CaptureGeometry.blurRadiusPixels(amount: 2, pixelScale: 2), 24)
    }

    func testImagePixelRectFlipsAndScales() {
        let rect = CaptureGeometry.imagePixelRect(
            forTopLeftPointRect: CGRect(x: 10, y: 5, width: 20, height: 10),
            imagePointSize: CGSize(width: 100, height: 60),
            imagePixelSize: CGSize(width: 200, height: 120)
        )
        XCTAssertEqual(rect, CGRect(x: 20, y: 90, width: 40, height: 20))

        // Expands outward to whole pixels and clips to the image.
        let clipped = CaptureGeometry.imagePixelRect(
            forTopLeftPointRect: CGRect(x: -5, y: 0.25, width: 20.2, height: 10),
            imagePointSize: CGSize(width: 100, height: 60),
            imagePixelSize: CGSize(width: 200, height: 120)
        )
        XCTAssertEqual(clipped, CGRect(x: 0, y: 99, width: 31, height: 21))

        XCTAssertNil(CaptureGeometry.imagePixelRect(
            forTopLeftPointRect: CGRect(x: 200, y: 0, width: 10, height: 10),
            imagePointSize: CGSize(width: 100, height: 60),
            imagePixelSize: CGSize(width: 200, height: 120)
        ))
    }
}

// MARK: - Blur / pixelate on synthetic images

final class ImageEffectTests: XCTestCase {
    /// 100×60 pt image at 2× (200×120 px).
    private let pointSize = CGSize(width: 100, height: 60)
    private let pixelScale = 2

    func testBlurChangesOnlyTheRegionAndMakesItUniform() throws {
        // 16 px cells (8 pt) — roughly the stroke spacing of body text on a Retina capture.
        let image = try XCTUnwrap(TestBitmap.checkerboard(pointSize: pointSize, scale: pixelScale, cell: 16))
        let original = try XCTUnwrap(TestBitmap.rgba(image))
        // Region touches the left image edge to check the edge doesn't fade to transparent.
        let rect = CGRect(x: 0, y: 10, width: 50, height: 30)

        // Default editor amount (AnnotationElement.effectAmount for the default line width).
        let blurred = try XCTUnwrap(image.blur(amount: 6, rect: rect))
        XCTAssertEqual(blurred.size, pointSize)
        let result = try XCTUnwrap(TestBitmap.rgba(blurred))
        XCTAssertEqual(result.width, original.width)
        XCTAssertEqual(result.height, original.height)

        let region = pixelRegion(rect)
        assertOutsideUnchanged(original: original, result: result, region: region)

        var minRed = 255, maxRed = 0
        for y in region.rows {
            for x in region.columns {
                let pixel = result.pixel(x: x, y: y)
                XCTAssertEqual(pixel.a, 255, "pixel (\(x), \(y)) should stay opaque")
                minRed = min(minRed, Int(pixel.r))
                maxRed = max(maxRed, Int(pixel.r))
            }
        }
        // Clamping the region's edges leaves a gentle low-frequency gradient, but the cell pattern must be gone:
        // horizontally neighbouring cells (originally black vs white, 255 apart) must now look the same.
        var maxCellContrast = 0
        for y in region.rows {
            for x in region.columns where region.columns.contains(x + 16) {
                maxCellContrast = max(maxCellContrast, abs(Int(result.pixel(x: x, y: y).r) - Int(result.pixel(x: x + 16, y: y).r)))
            }
        }
        // (Measured: range 29, contrast 14 — the residue is the edge-clamp gradient, not the pattern.)
        XCTAssertLessThanOrEqual(maxRed - minRed, 48, "blurred region should be near-uniform")
        XCTAssertLessThanOrEqual(maxCellContrast, 24, "the checkerboard pattern must not survive the default blur")
    }

    func testOldUnscaledBlurRadiusWouldLeaveThePatternVisible() throws {
        // Guards the metric above: a 6 px radius (the previous behaviour at the default amount on a 2x image)
        // keeps strong cell contrast, so the assertion in the test above is meaningful.
        let image = try XCTUnwrap(TestBitmap.checkerboard(pointSize: pointSize, scale: pixelScale, cell: 16))
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let input = CIImage(cgImage: cgImage).clampedToExtent()
        let filter = try XCTUnwrap(CIFilter(name: "CIGaussianBlur"))
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(6, forKey: kCIInputRadiusKey)
        let output = try XCTUnwrap(filter.outputImage?.cropped(to: CIImage(cgImage: cgImage).extent))
        let weak = try XCTUnwrap(CIContext().createCGImage(output, from: output.extent))
        let pixels = try XCTUnwrap(TestBitmap.rgba(weak))
        var maxCellContrast = 0
        for y in 20..<80 {
            for x in 0..<84 {
                maxCellContrast = max(maxCellContrast, abs(Int(pixels.pixel(x: x, y: y).r) - Int(pixels.pixel(x: x + 16, y: y).r)))
            }
        }
        XCTAssertGreaterThan(maxCellContrast, 60)
    }

    func testPixelateChangesOnlyTheRegionIntoBlocks() throws {
        // 1 px cells: no two horizontally adjacent pixels are equal before pixelation.
        let image = try XCTUnwrap(TestBitmap.checkerboard(pointSize: pointSize, scale: pixelScale, cell: 1))
        let original = try XCTUnwrap(TestBitmap.rgba(image))
        let rect = CGRect(x: 10, y: 10, width: 40, height: 20)

        let pixelated = try XCTUnwrap(image.pixelate(amount: 10, rect: rect))
        let result = try XCTUnwrap(TestBitmap.rgba(pixelated))

        let region = pixelRegion(rect)
        assertOutsideUnchanged(original: original, result: result, region: region)

        var equalPairs = 0, pairs = 0
        for y in region.rows {
            for x in region.columns.dropLast() {
                pairs += 1
                let a = result.pixel(x: x, y: y), b = result.pixel(x: x + 1, y: y)
                if a.r == b.r, a.g == b.g, a.b == b.b { equalPairs += 1 }
                XCTAssertEqual(a.a, 255)
            }
        }
        XCTAssertGreaterThan(Double(equalPairs) / Double(pairs), 0.9)
    }

    func testEffectsOutsideTheImageReturnNil() throws {
        let image = try XCTUnwrap(TestBitmap.checkerboard(pointSize: pointSize, scale: pixelScale, cell: 4))
        XCTAssertNil(image.blur(amount: 6, rect: CGRect(x: 500, y: 500, width: 10, height: 10)))
        XCTAssertNil(image.pixelate(amount: 10, rect: CGRect(x: 500, y: 500, width: 10, height: 10)))
    }

    // MARK: Helpers

    private struct PixelRegion {
        let columns: Range<Int>
        let rows: Range<Int>
        func contains(x: Int, y: Int) -> Bool { columns.contains(x) && rows.contains(y) }
    }

    /// Image-point rect (top-left origin) → pixel rows/columns in top-down memory order.
    private func pixelRegion(_ rect: CGRect) -> PixelRegion {
        PixelRegion(
            columns: Int(rect.minX) * pixelScale..<Int(rect.maxX) * pixelScale,
            rows: Int(rect.minY) * pixelScale..<Int(rect.maxY) * pixelScale
        )
    }

    private func assertOutsideUnchanged(
        original: TestBitmap.Pixels,
        result: TestBitmap.Pixels,
        region: PixelRegion,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var mismatches = 0
        for y in 0..<original.height {
            for x in 0..<original.width where !region.contains(x: x, y: y) {
                let a = original.pixel(x: x, y: y), b = result.pixel(x: x, y: y)
                if abs(Int(a.r) - Int(b.r)) > 2 || abs(Int(a.g) - Int(b.g)) > 2
                    || abs(Int(a.b) - Int(b.b)) > 2 || a.a != b.a {
                    mismatches += 1
                }
            }
        }
        XCTAssertEqual(mismatches, 0, "pixels outside the effect rect must be unchanged", file: file, line: line)
    }
}

// MARK: - Bitmap helpers

enum TestBitmap {
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        /// `y` counts from the top row.
        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let i = (y * width + x) * 4
            return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
        }
    }

    static func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func solid(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage? {
        guard let context = makeContext(width: 1, height: 1) else { return nil }
        context.setFillColor(CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
    }

    static func checkerboard(pointSize: CGSize, scale: Int, cell: Int) -> NSImage? {
        let width = Int(pointSize.width) * scale
        let height = Int(pointSize.height) * scale
        guard let context = makeContext(width: width, height: height) else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for row in 0..<(height / cell) {
            for column in 0..<(width / cell) where (row + column) % 2 == 0 {
                context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
            }
        }
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: pointSize)
    }

    static func rgba(_ image: NSImage) -> Pixels? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return rgba(cgImage)
    }

    static func rgba(_ image: CGImage) -> Pixels? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = makeContext(width: width, height: height, data: buffer.baseAddress) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? Pixels(width: width, height: height, bytes: bytes) : nil
    }
}
