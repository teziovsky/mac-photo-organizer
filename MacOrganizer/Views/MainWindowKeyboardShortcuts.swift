import SwiftUI

/// Keyboard shortcuts scoped to the main window view hierarchy (inactive while Settings is focused).
struct MainWindowKeyboardShortcuts: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            Button("") {
                Task { await appState.selectPreviousAlbum() }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .hidden()
            .disabled(!appState.canSelectPreviousAlbum)

            Button("") {
                Task { await appState.selectNextAlbum() }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .hidden()
            .disabled(!appState.canSelectNextAlbum)

            Button("") {
                Task { await appState.previewSelectedMedia() }
            }
            .keyboardShortcut("y", modifiers: .command)
            .hidden()
            .disabled(appState.selectedMediaID == nil)

            Button("") {
                appState.decreaseMediaGridColumnCount()
            }
            .keyboardShortcut("+", modifiers: .command)
            .hidden()
            .disabled(appState.selectedAlbum == nil || !appState.canDecreaseMediaGridColumnCount)

            Button("") {
                appState.increaseMediaGridColumnCount()
            }
            .keyboardShortcut("-", modifiers: .command)
            .hidden()
            .disabled(appState.selectedAlbum == nil || !appState.canIncreaseMediaGridColumnCount)

            Button("") {
                appState.toggleThumbnailDisplayMode()
            }
            .keyboardShortcut("t", modifiers: .command)
            .hidden()
            .disabled(appState.selectedAlbum == nil)

            Button("") {
                Task { await appState.photosService.reloadAlbums() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
            .disabled(appState.photosService.isLoadingAlbums)

            Button("") {
                appState.focusAlbumSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()

            Button("") {
                if AppSettings.resolveExportDirectory() == nil {
                    return
                }
                appState.startOrganize()
            }
            .keyboardShortcut("e", modifiers: .command)
            .hidden()
            .disabled(
                appState.selectedAlbum == nil
                    || appState.mediaItems.isEmpty
                    || appState.organizeExporter.isRunning
                    || !appState.canOrganizeSelectedAlbum
                    || AppSettings.resolveExportDirectory() == nil
            )

            Button("") {
                appState.toggleSidebarVisibility()
            }
            .keyboardShortcut("s", modifiers: .command)
            .hidden()
        }
    }

}
