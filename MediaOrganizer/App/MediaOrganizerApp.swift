import AppKit
import SwiftUI

@main
struct MediaOrganizerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 700)
                .task {
                    await appState.bootstrap()
                }
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    appState.toggleSidebarVisibility()
                }
            }
            MediaOrganizerAlbumCommands(appState: appState)
            CommandGroup(after: .sidebar) {
                Button("Refresh Albums") {
                    Task { await appState.photosService.reloadAlbums() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.photosService.isLoadingAlbums)

                Button("Toggle Thumbnail Display") {
                    appState.toggleThumbnailDisplayMode()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.selectedAlbum == nil)

                Divider()

                Button("Organize Album") {
                    appState.promptExportDirectoryAndOrganize()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(
                    appState.selectedAlbum == nil
                        || appState.mediaItems.isEmpty
                        || appState.organizeExporter.isRunning
                        || !appState.canOrganizeSelectedAlbum
                )

                Divider()

                Button("Quick Look") {
                    Task { await appState.previewSelectedMedia() }
                }
                .disabled(appState.selectedMediaID == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct MediaOrganizerAlbumCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Albums") {
            ForEach(Array(appState.selectableAlbums.prefix(9).enumerated()), id: \.element.id) { index, album in
                Button(album.name) {
                    Task { await appState.selectAlbum(at: index) }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .disabled(!appState.selectableAlbums.indices.contains(index))
            }

            Divider()

            Button("Next Album") {
                Task { await appState.selectNextAlbum() }
            }
            .disabled(!appState.canSelectNextAlbum)

            Button("Previous Album") {
                Task { await appState.selectPreviousAlbum() }
            }
            .disabled(!appState.canSelectPreviousAlbum)
        }
    }
}

