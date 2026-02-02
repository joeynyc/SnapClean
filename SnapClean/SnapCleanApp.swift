import SwiftUI

@main
struct SnapCleanApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SnapClean") {
                    appState.showAboutWindow = true
                }
            }
            CommandGroup(after: .appSettings) {
                Button("Preferences...") {
                    appState.showPreferences = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        MenuBarExtra("SnapClean", systemImage: "camera.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
