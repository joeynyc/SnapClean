import SwiftUI

/// Full-screen capture overlay shown on one screen.
///
/// Pointer locations are read in SwiftUI's `.global` space, which inside the overlay's `NSHostingView` is
/// overlay-local (top-left of the overlay window). `overlayDisplayFrame` maps that to the global display
/// space ScreenCaptureKit uses; see `CaptureGeometry`.
struct CaptureOverlay: View {
    @Environment(AppState.self) var appState
    let mode: CaptureMode
    /// This overlay window's frame in global display space (top-left origin of the primary display).
    let overlayDisplayFrame: CGRect
    /// Height of the primary display, for converting Cocoa mouse locations.
    let primaryScreenHeight: CGFloat

    /// Region selection in overlay-local coordinates.
    @State private var captureRect: CGRect = .zero
    @State private var isDragging = false
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isCapturingSelection = false

    /// Windows visible on this overlay, overlay-local and clipped, ordered front to back.
    @State private var overlayWindows: [CapturableWindow] = []
    @State private var hoveredWindowID: CGWindowID?
    @State private var selectedWindowID: CGWindowID?

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            switch mode {
            case .region:
                regionSelectionView
            case .window:
                windowSelectionView
            case .screen:
                screenCaptureView
            }

            // Cancel instruction
            VStack {
                Spacer()
                HStack {
                    Text("Press ESC to cancel")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                }
                .padding(.bottom, 20)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Region Selection

    private var regionSelectionView: some View {
        GeometryReader { geometry in
            let globalFrame = geometry.frame(in: .global)
            let localRect = captureRect.offsetBy(dx: -globalFrame.origin.x, dy: -globalFrame.origin.y)
            ZStack {
                // Hit-testable background so drags anywhere on the overlay are received.
                Color.clear

                // Selection rectangle
                if isDragging || captureRect != .zero {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.1))
                        .frame(width: localRect.width, height: localRect.height)
                        .position(x: localRect.midX, y: localRect.midY)

                    // Size indicator
                    VStack {
                        Text("\(Int(captureRect.width)) × \(Int(captureRect.height))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                    }
                    .position(x: localRect.maxX + 40, y: localRect.minY - 20)
                }
            }
            .contentShape(Rectangle())
            // The system crosshair replaces a drawn crosshair, which could only follow drags.
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.crosshair.set()
                case .ended:
                    break
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        guard !isCapturingSelection else { return }
                        if !isDragging {
                            startPoint = value.startLocation
                            isDragging = true
                        }
                        currentPoint = value.location
                        updateCaptureRect()
                    }
                    .onEnded { _ in
                        guard !isCapturingSelection else { return }
                        if captureRect.width > 10 && captureRect.height > 10 {
                            performCapture()
                        } else {
                            isDragging = false
                            captureRect = .zero
                        }
                    }
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Window Selection

    private var windowSelectionView: some View {
        GeometryReader { geometry in
            let globalFrame = geometry.frame(in: .global)
            let hoveredWindow = overlayWindows.first { $0.id == hoveredWindowID }
            ZStack {
                Color.clear

                if let hoveredWindow {
                    WindowHighlightView(
                        name: hoveredWindow.name,
                        displayBounds: hoveredWindow.bounds.offsetBy(
                            dx: -globalFrame.origin.x,
                            dy: -globalFrame.origin.y
                        ),
                        isSelected: selectedWindowID == hoveredWindow.id
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .global) { phase in
                guard selectedWindowID == nil else { return }
                switch phase {
                case .active(let location):
                    hoveredWindowID = CaptureGeometry.frontmostWindow(at: location, in: overlayWindows)?.id
                case .ended:
                    hoveredWindowID = nil
                }
            }
            .gesture(
                SpatialTapGesture(coordinateSpace: .global)
                    .onEnded { value in
                        guard selectedWindowID == nil,
                              let window = CaptureGeometry.frontmostWindow(at: value.location, in: overlayWindows) else {
                            return
                        }
                        hoveredWindowID = window.id
                        selectedWindowID = window.id
                        performWindowCapture(windowID: window.id)
                    }
            )
            .task {
                let windows = await appState.capture.screenCapture.getWindowList()
                overlayWindows = CaptureGeometry.overlayWindows(windows, overlayDisplayFrame: overlayDisplayFrame)
                seedHoverFromMouseLocation()
            }
        }
        .ignoresSafeArea()
    }

    /// Highlights the window under the pointer before the first mouse move, which is when hover starts reporting.
    private func seedHoverFromMouseLocation() {
        guard hoveredWindowID == nil else { return }
        let displayPoint = CaptureGeometry.displayPoint(
            fromCocoa: NSEvent.mouseLocation,
            primaryScreenHeight: primaryScreenHeight
        )
        let localPoint = CaptureGeometry.overlayLocalPoint(
            fromDisplay: displayPoint,
            overlayDisplayFrame: overlayDisplayFrame
        )
        hoveredWindowID = CaptureGeometry.frontmostWindow(at: localPoint, in: overlayWindows)?.id
    }

    // MARK: - Screen Capture

    private var screenCaptureView: some View {
        VStack(spacing: 20) {
            if appState.capture.captureCountdown > 0 {
                Text("\(appState.capture.captureCountdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 10)

                Text("Preparing to capture...")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Capturing...")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    // MARK: - Helper Methods

    private func updateCaptureRect() {
        let x = min(startPoint.x, currentPoint.x)
        let y = min(startPoint.y, currentPoint.y)
        let width = abs(currentPoint.x - startPoint.x)
        let height = abs(currentPoint.y - startPoint.y)
        captureRect = CGRect(x: x, y: y, width: width, height: height)
    }

    private func performCapture() {
        guard mode == .region else { return }
        isCapturingSelection = true
        // A drag may extend past this overlay onto a neighbouring display; the capture service stitches it.
        let rect = CaptureGeometry.displayRect(fromOverlayLocal: captureRect, overlayDisplayFrame: overlayDisplayFrame)
        Task { @MainActor in
            let image = await appState.capture.screenCapture.captureRegion(rect: rect)
            if let img = image {
                appState.handleCapturedImage(img)
            } else {
                appState.endCaptureRestoringWindow(failure: .captureFailed(.region))
            }
        }
    }

    private func performWindowCapture(windowID: CGWindowID) {
        Task { @MainActor in
            let image = await appState.capture.screenCapture.captureWindowByID(windowID)
            if let image {
                appState.handleCapturedImage(image)
            } else {
                appState.endCaptureRestoringWindow(failure: .captureFailed(.window))
            }
        }
    }
}

struct WindowHighlightView: View {
    let name: String
    /// Overlay-local bounds, already clipped to the overlay.
    let displayBounds: CGRect
    let isSelected: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.accentColor.opacity(isSelected ? 0.3 : 0.18))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: isSelected ? 3 : 2))
                .frame(width: displayBounds.width, height: displayBounds.height)
                .position(x: displayBounds.midX, y: displayBounds.midY)

            Text(name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .frame(maxWidth: max(displayBounds.width, 120))
                // Above the window, or just inside its top edge when it touches the top of the screen.
                .position(x: displayBounds.midX, y: displayBounds.minY >= 30 ? displayBounds.minY - 15 : displayBounds.minY + 15)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
