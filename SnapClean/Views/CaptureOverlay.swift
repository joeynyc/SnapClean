import SwiftUI

struct CaptureOverlay: View {
    @EnvironmentObject var appState: AppState
    let mode: CaptureMode

    @State private var captureRect: CGRect = .zero
    @State private var isDragging = false
    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var selectedWindow: (id: CGWindowID, name: String, bounds: CGRect)?
    @State private var timer: Timer?
    @State private var countdown: Int = 0
    @State private var keyMonitor: Any?

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
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // ESC
                    cancelCapture()
                    return nil
                }
                return event
            }
            if mode == .screen {
                startTimerCapture()
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    // MARK: - Region Selection

    private var regionSelectionView: some View {
        GeometryReader { geometry in
            ZStack {
                // Selection rectangle
                if isDragging || captureRect != .zero {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.1))
                        .frame(width: captureRect.width, height: captureRect.height)
                        .position(x: captureRect.midX, y: captureRect.midY)

                    // Size indicator
                    VStack {
                        Text("\(Int(captureRect.width)) × \(Int(captureRect.height))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.7)))
                    }
                    .position(x: captureRect.maxX + 40, y: captureRect.minY - 20)
                }

                // Crosshair cursor
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(.white)
                    .position(currentPoint)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            startPoint = value.location
                            isDragging = true
                        }
                        currentPoint = value.location
                        updateCaptureRect()
                    }
                    .onEnded { value in
                        if captureRect.width > 10 && captureRect.height > 10 {
                            performCapture()
                        } else {
                            isDragging = false
                            captureRect = .zero
                        }
                    }
            )
        }
    }

    // MARK: - Window Selection

    private var windowSelectionView: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(appState.screenCapture.getWindowList(), id: \.id) { window in
                    WindowHighlightView(
                        window: window,
                        isSelected: selectedWindow?.id == window.id
                    )
                    .onTapGesture {
                        selectedWindow = window
                        performWindowCapture(window: window)
                    }
                }
            }
        }
    }

    // MARK: - Screen Capture

    private var screenCaptureView: some View {
        VStack(spacing: 20) {
            if countdown > 0 {
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(radius: 10)

                Text("Preparing to capture...")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)

                Text("Capturing...")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
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

    private func startTimerCapture() {
        countdown = appState.timerDuration
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer?.invalidate()
                performCapture()
            }
        }
    }

    private func performCapture() {
        timer?.invalidate()

        let image: NSImage?
        switch mode {
        case .region:
            image = appState.screenCapture.captureRegion(rect: captureRect)
        case .window:
            image = nil
        case .screen:
            image = appState.screenCapture.captureFullScreen()
        }

        if let img = image {
            appState.handleCapturedImage(img)
        }
    }

    private func performWindowCapture(window: (id: CGWindowID, name: String, bounds: CGRect)) {
        if let image = appState.screenCapture.captureWindowByID(window.id, bounds: window.bounds) {
            appState.handleCapturedImage(image)
        }
    }

    private func cancelCapture() {
        timer?.invalidate()
        appState.isCapturing = false
    }
}

struct WindowHighlightView: View {
    let window: (id: CGWindowID, name: String, bounds: CGRect)
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .stroke(isSelected ? Color.accentColor : Color.white, lineWidth: isSelected ? 3 : 1)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.1))
            .frame(width: window.bounds.width, height: window.bounds.height)
            .position(x: window.bounds.midX, y: window.bounds.midY)
            .overlay(
                Text(window.name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .position(x: window.bounds.midX, y: window.bounds.minY - 15)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
