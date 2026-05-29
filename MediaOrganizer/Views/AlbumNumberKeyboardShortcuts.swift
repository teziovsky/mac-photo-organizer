import SwiftUI

/// ⌘1–⌘9: select album by index (no toggle; Escape deselects). Mounted on the grid so shortcuts work while it has focus.
struct AlbumNumberKeyboardShortcuts: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            ForEach(1...9, id: \.self) { number in
                Button("Select album \(number)") {
                    Task { await appState.selectAlbum(at: number - 1) }
                }
                .keyboardShortcut(shortcutKey(number), modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
                .disabled(!appState.selectableAlbums.indices.contains(number - 1))
            }
        }
        .allowsHitTesting(false)
    }

    private func shortcutKey(_ number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(number)))
    }
}
