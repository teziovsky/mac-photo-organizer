import SwiftUI

/// Keyboard shortcuts scoped to the main window view hierarchy (inactive while Settings is focused).
struct MainWindowKeyboardShortcuts: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            shortcutButton("Previous album", enabled: appState.canSelectPreviousAlbum) {
                Task { await appState.selectPreviousAlbum() }
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            shortcutButton("Next album", enabled: appState.canSelectNextAlbum) {
                Task { await appState.selectNextAlbum() }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

            shortcutButton("Quick Look", enabled: appState.selectedMediaID != nil) {
                Task { await appState.previewSelectedMedia() }
            }
            .keyboardShortcut("y", modifiers: .command)

            shortcutButton("Larger thumbnails", enabled: appState.selectedAlbum != nil && appState.canDecreaseMediaGridColumnCount) {
                appState.decreaseMediaGridColumnCount()
            }
            .keyboardShortcut("+", modifiers: .command)

            shortcutButton("Smaller thumbnails", enabled: appState.selectedAlbum != nil && appState.canIncreaseMediaGridColumnCount) {
                appState.increaseMediaGridColumnCount()
            }
            .keyboardShortcut("-", modifiers: .command)

            shortcutButton("Toggle thumbnail display", enabled: appState.selectedAlbum != nil) {
                appState.toggleThumbnailDisplayMode()
            }
            .keyboardShortcut("t", modifiers: .command)

            shortcutButton("Refresh albums", enabled: !appState.photosService.isLoadingAlbums) {
                Task { await appState.photosService.reloadAlbums() }
            }
            .keyboardShortcut("r", modifiers: .command)

            shortcutButton("Organize album", enabled: appState.canOrganizeSelectedAlbum && !appState.mediaItems.isEmpty && !appState.organizeExporter.isRunning) {
                appState.promptExportDirectoryAndOrganize()
            }
            .keyboardShortcut("e", modifiers: .command)

            shortcutButton("Toggle sidebar", enabled: true) {
                appState.toggleSidebarVisibility()
            }
            .keyboardShortcut("s", modifiers: .command)
        }
    }

    private func shortcutButton(
        _ label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(label, action: action)
            .hidden()
            .accessibilityHidden(true)
            .disabled(!enabled)
    }
}
