import SwiftUI
import AppKit

@MainActor
class CaptureState: ObservableObject {
    @Published var isCapturing = false
    @Published var currentCaptureMode: CaptureMode = .region
    @Published var capturedImage: NSImage?
    @Published var showAnnotationCanvas = false
    @Published var captureCountdown: Int = 0
    @Published private(set) var screenCapturePermissionStatus: ScreenCapturePermissionStatus = .unknown

    let screenCapture = ScreenCaptureService()
    private var captureTimer: Timer?
    private var wasMainWindowVisibleBeforeCapture = false
    private let screenCaptureAccessPromptedKey = "didPromptScreenCaptureAccess"

    func startCapture(mode: CaptureMode, countdown: Int = 0) {
        // Implementation will be moved from AppState
    }

    func cancelCapture() {
        // Implementation will be moved from AppState
    }

    func handleCapturedImage(_ image: NSImage) {
        // Implementation will be moved from AppState
    }

    func checkScreenCapturePermission() {
        // Implementation will be moved from AppState
    }

    func refreshScreenCapturePermissionStatus() {
        // Implementation will be moved from AppState
    }

    func requestScreenCaptureAccess() {
        // Implementation will be moved from AppState
    }
}
