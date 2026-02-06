import SwiftUI
import AppKit

struct MainWindow: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            if appState.showAnnotationCanvas, let image = appState.capturedImage {
                AnnotationCanvasView(image: image)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(
            WindowAccessor { window in
                guard let window else { return }
                if let current = appState.mainWindow, current === window {
                    return
                }
                window.identifier = NSUserInterfaceItemIdentifier("MainWindow")
                appState.mainWindow = window
            }
        )
        .sheet(isPresented: $appState.showPinWindow) {
            PinWindow()
                .environmentObject(appState)
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("SnapClean")
                    .font(.system(size: 32, weight: .bold, design: .rounded))

                Text("Beautiful screenshots, made simple.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)

            Spacer()

            // Quick Actions
            VStack(spacing: 16) {
                if appState.screenCapturePermissionStatus == .denied {
                    ScreenCapturePermissionNotice()
                }

                CaptureButton(
                    title: "Capture Region",
                    subtitle: "Draw a rectangle to capture",
                    icon: "square.dashed",
                    keyboard: "F1"
                ) {
                    appState.startCapture(mode: .region)
                }

                CaptureButton(
                    title: "Capture Window",
                    subtitle: "Click to capture a window",
                    icon: "app.windows",
                    keyboard: "F2"
                ) {
                    appState.startCapture(mode: .window)
                }

                CaptureButton(
                    title: "Capture Screen",
                    subtitle: "Capture the entire screen",
                    icon: "desktopcomputer",
                    keyboard: "F3"
                ) {
                    appState.startCapture(mode: .screen)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Recent History Preview
            if !appState.screenshotHistory.isEmpty {
                RecentHistoryView()
                    .padding(.bottom, 20)
            }
        }
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        .onAppear {
            appState.refreshScreenCapturePermissionStatus()
        }
    }
}

struct ScreenCapturePermissionNotice: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording Permission Needed")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("Enable Screen Recording for SnapClean in System Settings to capture screenshots.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open System Settings") {
                appState.openScreenCaptureSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

struct CaptureButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let keyboard: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(keyboard)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct RecentHistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent Screenshots")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Button("View All") {
                    appState.showHistory = true
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.screenshotHistory.prefix(5)) { item in
                        HistoryThumbnailView(item: item)
                    }
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .padding(.horizontal, 20)
    }
}

struct HistoryThumbnailView: View {
    let item: ScreenshotItem
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button {
            if let image = NSImage(contentsOfFile: item.filePath) {
                appState.pinnedImage = image
                appState.showPinWindow = true
            }
        } label: {
            VStack(spacing: 4) {
                if let thumbnailData = item.thumbnail,
                   let nsImage = NSImage(data: thumbnailData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Text(item.date, style: .time)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    MainWindow()
        .environmentObject(AppState())
}
