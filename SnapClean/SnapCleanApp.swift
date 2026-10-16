import SwiftUI

enum SnapCleanWindowID {
    static let main = "main"
    static let history = "history"
    static let about = "about"
}

@main
struct SnapCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        Window("SnapClean", id: SnapCleanWindowID.main) {
            MainWindow()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SnapClean") {
                    openWindow(id: SnapCleanWindowID.about)
                }
            }
            CommandGroup(after: .windowList) {
                Button("History") {
                    openWindow(id: SnapCleanWindowID.history)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Preferences...")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarExtraLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environment(appState)
                .frame(width: 600, height: 400)
        }

        WindowGroup("History", id: SnapCleanWindowID.history) {
            HistoryPanel()
                .environment(appState)
        }
        .defaultSize(width: 620, height: 560)

        WindowGroup("About SnapClean", id: SnapCleanWindowID.about) {
            AboutView()
        }
        .defaultSize(width: 420, height: 300)
    }
}

/// The menu bar icon is the one view that exists for the app's whole lifetime, so it hands
/// `openWindow` to AppState for captures that finish while the main window is closed.
private struct MenuBarExtraLabel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "camera.fill")
            .accessibilityLabel("SnapClean")
            .onAppear {
                appState.capture.openMainWindow = { [openWindow] in
                    openWindow(id: SnapCleanWindowID.main)
                }
            }
    }
}
