import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
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
                        title: "Appearance",
                        icon: "paintbrush",
                        isSelected: selectedTab == 2
                    ) {
                        selectedTab = 2
                    }

                    PreferencesTabButton(
                        title: "Storage",
                        icon: "internaldrive",
                        isSelected: selectedTab == 3
                    ) {
                        selectedTab = 3
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
                        AppearancePreferencesView()
                    case 3:
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
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .primary : .secondary)

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
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Save location
            VStack(alignment: .leading, spacing: 8) {
                    Text("Default Save Location")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                HStack {
                    Text("Documents/SnapClean/History")
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
                Toggle(isOn: Binding(get: { appState.copyAfterCapture }, set: { appState.copyAfterCapture = $0 })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Copy to clipboard after capture")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("Automatically copy screenshots to clipboard")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(PreferencesToggleStyle())

                Toggle(isOn: Binding(get: { appState.showPreviewAfterCapture }, set: { appState.showPreviewAfterCapture = $0 })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Show preview after capture")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("Display annotation editor after taking screenshot")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
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
                    ForEach([3, 5, 10], id: \.self) { seconds in
                        Button {
                            appState.timerDuration = seconds
                        } label: {
                            Text("\(seconds)s")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(spacing: 8) {
                ShortcutRow(name: "Capture Region", shortcut: "F1")
                ShortcutRow(name: "Capture Window", shortcut: "F2")
                ShortcutRow(name: "Capture Screen", shortcut: "F3")
                ShortcutRow(name: "Undo", shortcut: "⌘Z")
                ShortcutRow(name: "Redo", shortcut: "⌘⇧Z")
                ShortcutRow(name: "Save", shortcut: "⌘S")
                ShortcutRow(name: "Copy", shortcut: "⌘C")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Text("Note: Some shortcuts may conflict with system or other apps.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)

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

struct AppearancePreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            // Theme
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Theme")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Coming Soon")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }

                HStack(spacing: 12) {
                    Button {
                    } label: {
                        VStack {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 24))
                            Text("Dark")
                                .font(.system(size: 11, design: .rounded))
                        }
                        .frame(width: 80, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(true)

                    Button {
                    } label: {
                        VStack {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 24))
                            Text("Light")
                                .font(.system(size: 11, design: .rounded))
                        }
                        .frame(width: 80, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                }
            }

            Divider()

            // Toolbar style
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    Text("Toolbar Style")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Coming Soon")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }

                Picker("", selection: .constant(0)) {
                    Text("Glass Effect").tag(0)
                    Text("Solid").tag(1)
                    Text("Minimal").tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(true)
            }

            Spacer()
        }
        .padding(24)
    }
}

struct StoragePreferencesView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Storage")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 12) {
                Text("Screenshot History")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                HStack {
                    Text("Keep last")
                        .font(.system(size: 13, design: .rounded))

                    TextField("50", value: Binding(
                        get: { appState.historyLimit },
                        set: { appState.historyLimit = $0 }
                    ), format: .number)
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
                        appState.clearHistory()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Open History Folder") {
                        NSWorkspace.shared.open(appState.historyManager.saveDirectory)
                    }
                    .buttonStyle(.bordered)
                }
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
        .environmentObject(AppState())
}
