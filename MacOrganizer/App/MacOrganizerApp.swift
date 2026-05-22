import SwiftUI

@main
struct MacOrganizerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 700)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            MacOrganizerSettingsCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct MacOrganizerSettingsCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appState.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
