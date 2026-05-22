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
            MacOrganizerAlbumCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct MacOrganizerAlbumCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Albums") {
            ForEach(Array(appState.selectableAlbums.prefix(9).enumerated()), id: \.element.id) { index, album in
                Button(album.name) {
                    Task { await appState.selectAlbum(at: index) }
                }
                .keyboardShortcut(albumShortcutKey(index), modifiers: .command)
            }

            Divider()

            Button("Next Album") {
                Task { await appState.selectNextAlbum() }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(!appState.canSelectNextAlbum)

            Button("Previous Album") {
                Task { await appState.selectPreviousAlbum() }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!appState.canSelectPreviousAlbum)
        }
    }

    private func albumShortcutKey(_ index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}
