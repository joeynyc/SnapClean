import SwiftUI

enum SnapCleanWindowID {
    static let history = "history"
    static let about = "about"
}

@main
struct SnapCleanApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    appDelegate.appState = appState
                }
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

        MenuBarExtra("SnapClean", systemImage: "camera.fill") {
            MenuBarView()
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
