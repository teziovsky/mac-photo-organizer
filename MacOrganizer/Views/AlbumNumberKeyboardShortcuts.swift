import SwiftUI

/// ⌘1–⌘9 album shortcuts; mounted on the grid so they work while the grid has focus.
struct AlbumNumberKeyboardShortcuts: View {
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
        }
        .allowsHitTesting(false)
    }

    private func shortcutKey(_ number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(number)))
    }
}
