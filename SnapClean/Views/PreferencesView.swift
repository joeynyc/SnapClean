import SwiftUI

struct PreferencesView: View {
    @Environment(AppState.self) var appState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Sidebar
                VStack(alignment: .leading, spacing: 4) {
                    PreferencesTabButton(
                        title: "General",
                        icon: "gearshape",
                        isSelected: selectedTab == 0
                    ) {
                        selectedTab = 0
                    }

                    PreferencesTabButton(
                        title: "Shortcuts",
                        icon: "keyboard",
                        isSelected: selectedTab == 1
                    ) {
                        selectedTab = 1
                    }

                    PreferencesTabButton(
                        title: "Storage",
                        icon: "internaldrive",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }
                }
                .padding(12)
                .frame(width: 180)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Content
                Group {
                    switch selectedTab {
                    case 0:
                        GeneralPreferencesView()
                    case 1:
                        ShortcutsPreferencesView()
                    case 2:
                        StoragePreferencesView()
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 600, height: 400)
    }
}

struct PreferencesTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GeneralPreferencesView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 24) {
            // Save location
            VStack(alignment: .leading, spacing: 8) {
                    Text("Default Save Location")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                HStack {
                    Text(abbreviatedPath(appState.history.historyManager.saveDirectory))
                        .font(.system(size: 13, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))

                    Spacer()
                }
            }

            Divider()

            // Copy to clipboard
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $appState.copyAfterCapture) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Copy to clipboard after capture")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("Automatically copy screenshots to clipboard")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(PreferencesToggleStyle())

                Toggle(isOn: $appState.showPreviewAfterCapture) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show preview after capture")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("Display annotation editor after taking screenshot")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(PreferencesToggleStyle())
            }

            Divider()

            // Timer capture
            VStack(alignment: .leading, spacing: 12) {
                Text("Timer Duration")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                HStack(spacing: 12) {
                    ForEach([0, 3, 5, 10], id: \.self) { seconds in
                        Button {
                            appState.timerDuration = seconds
                        } label: {
                            Text(seconds == 0 ? "Off" : "\(seconds)s")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        appState.timerDuration == seconds
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.secondary.opacity(0.1)
                                    )
                                )
                                .overlay(
                                    Capsule().stroke(
                                        appState.timerDuration == seconds
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }
}

struct ShortcutsPreferencesView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Reset to Defaults") {
                    appState.resetShortcuts()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                ShortcutRecorderRow(name: "Capture Region", mode: .region)
                ShortcutRecorderRow(name: "Capture Window", mode: .window)
                ShortcutRecorderRow(name: "Capture Screen", mode: .screen)
                Divider()
                ShortcutRow(name: "Undo", shortcut: "⌘Z")
                ShortcutRow(name: "Redo", shortcut: "⇧⌘Z")
                ShortcutRow(name: "Save", shortcut: "⌘S")
                ShortcutRow(name: "Copy", shortcut: "⌘C")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Text("Click a capture shortcut, then press the new keys. Esc cancels. Shortcuts need ⌘, ⌃ or ⌥, except F-keys. Some shortcuts may conflict with the system or other apps.")
                .font(.system(size: 11, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}

struct ShortcutRow: View {
    let name: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, design: .rounded))
            Spacer()
            Text(shortcut)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }
}

struct ShortcutRecorderRow: View {
    @Environment(AppState.self) var appState
    let name: String
    let mode: CaptureMode

    @State private var isRecording = false
    @State private var keyMonitor: Any?

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 13, design: .rounded))
            Spacer()
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Type shortcut…" : appState.shortcut(for: mode).displayString)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .overlay(Capsule().stroke(isRecording ? Color.accentColor : .clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Click to record a new shortcut")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard !appState.isRecordingShortcut else { return }
        isRecording = true
        appState.isRecordingShortcut = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
            } else if let shortcut = HotkeyShortcut(event: event),
                      appState.setShortcut(shortcut, for: mode) {
                stopRecording()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isRecording = false
        appState.isRecordingShortcut = false
    }
}

struct StoragePreferencesView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 24) {
            Text("Storage")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 12) {
                Text("Screenshot History")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                HStack {
                    Text("Keep last")
                        .font(.system(size: 13, design: .rounded))

                    TextField("50", value: $appState.historyLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)

                    Text("screenshots")
                        .font(.system(size: 13, design: .rounded))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Clear History", role: .destructive) {
                        appState.history.clearHistory()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Open Screenshots Folder") {
                        NSWorkspace.shared.open(appState.history.historyManager.saveDirectory)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Clearing history keeps your screenshot files in \(abbreviatedPath(appState.history.historyManager.saveDirectory)).")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
    }
}

struct PreferencesToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.label

            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }
}

#Preview {
    PreferencesView()
        .environment(AppState())
}

/// Shows paths under the user's home folder as "~/…". `NSHomeDirectory()` points into the sandbox
/// container, so the real home is derived from the default save directory (~/Downloads).
private func abbreviatedPath(_ url: URL) -> String {
    let home = ScreenshotHistoryManager.defaultSaveDirectory.deletingLastPathComponent().path
    return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
}
