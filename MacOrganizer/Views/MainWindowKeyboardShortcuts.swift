import SwiftUI

/// Keyboard shortcuts scoped to the main window view hierarchy (inactive while Settings is focused).
struct MainWindowKeyboardShortcuts: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            ForEach(1...9, id: \.self) { number in
                Button("") {
                    Task { await appState.selectAlbum(at: number - 1) }
                }
                .keyboardShortcut(shortcutKey(number), modifiers: .command)
                .hidden()
                .disabled(!appState.selectableAlbums.indices.contains(number - 1))
            }

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
                appState.toggleSidebarVisibility()
            }
            .keyboardShortcut("s", modifiers: .command)
            .hidden()
        }
    }

    private func shortcutKey(_ number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(number)))
    }
}
