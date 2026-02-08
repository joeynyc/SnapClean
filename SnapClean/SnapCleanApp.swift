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
                .onAppear {
                    appDelegate.appState = appState
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SnapClean") {
                    appState.showAboutWindow = true
                }
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
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environmentObject(appState)
                .frame(width: 600, height: 400)
        }
    }
}
