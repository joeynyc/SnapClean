import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 12) {
            // App title
            HStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(alignment: .leading, spacing: 2) {
                    Text("SnapClean")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Beautiful screenshots")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            Divider()

            if appState.capture.screenCapturePermissionStatus == .denied {
                MenuBarScreenCapturePermissionNotice()
                Divider()
            }

            // Quick capture buttons
            MenuButton(
                title: "Capture Region",
                subtitle: "Draw a selection",
                icon: "square.dashed",
                keyboard: "F1"
            ) {
                appState.startCapture(mode: .region)
            }

            MenuButton(
                title: "Capture Window",
                subtitle: "Click a window",
                icon: "app.windows",
                keyboard: "F2"
            ) {
                appState.startCapture(mode: .window)
            }

            MenuButton(
                title: "Capture Screen",
                subtitle: "Full screen",
                icon: "desktopcomputer",
                keyboard: "F3"
            ) {
                appState.startCapture(mode: .screen)
            }

            Divider()

            // History
            Button {
                appState.showHistory = true
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .frame(width: 24)

                    Text("History")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    if !appState.history.screenshotHistory.isEmpty {
                        Text("\(appState.history.screenshotHistory.count)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Settings
            SettingsLink {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .frame(width: 24)

                    Text("Preferences")
                        .font(.system(size: 13, weight: .medium, design: .rounded))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Divider()

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .frame(width: 24)

                    Text("Quit SnapClean")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 250)
        .onAppear {
            appState.capture.refreshScreenCapturePermissionStatus()
        }
        .sheet(isPresented: $appState.showHistory) {
            HistoryPanel()
                .environment(appState)
        }
    }
}

struct MenuBarScreenCapturePermissionNotice: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Screen Recording is Off")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }

            Button("Open System Settings") {
                appState.capture.openScreenCaptureSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct MenuButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let keyboard: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isHovered ? Color.accentColor : .primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(isHovered ? Color.accentColor : .primary)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(keyboard)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
}
