import SwiftUI

struct AlbumSidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.photosService.authorizationState {
            case .notDetermined:
                ProgressView("Connecting to Photos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .authorized:
                albumList
            case .denied, .restricted:
                ContentUnavailableView(
                    "Photos Access Required",
                    systemImage: "lock.slash",
                    description: Text(
                        "Allow iCloud Photos Organizer to access your Photos library in System Settings.")
                )
            }
        }
        .frame(minWidth: 320, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 340, ideal: 360)
        .overlay {
            if appState.photosService.isLoadingAlbums {
                ProgressView()
                    .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var albumList: some View {
        if appState.selectableAlbums.isEmpty && !appState.photosService.isLoadingAlbums {
            ContentUnavailableView(
                "No Albums",
                systemImage: "folder",
                description: Text(emptyAlbumsDescription)
            )
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(appState.selectableAlbums.enumerated()), id: \.element.id) {
                        index, album in
                        AlbumSidebarListRow(
                            album: album,
                            shortcutIndex: index < 9 ? index + 1 : nil,
                            isSelected: appState.selectedAlbum?.id == album.id
                        ) {
                            Task { await appState.toggleAlbumSelection(album) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .frame(minWidth: 320, maxHeight: .infinity)
        }
    }

    private var emptyAlbumsDescription: String {
        let suffix = AppSettings.excludedAlbumSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        if suffix.isEmpty {
            return "No non-empty albums were found in Photos."
        }
        return "No non-empty albums without the \"\(suffix)\" suffix were found in Photos."
    }
}

private struct AlbumSidebarListRow: View {
    let album: PhotoAlbum
    let shortcutIndex: Int?
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        AlbumListRowLabels(album: album, shortcutIndex: shortcutIndex)
            .albumListRowChrome(backgroundFill: rowBackgroundFill)
            .onTapGesture(perform: onSelect)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private var rowBackgroundFill: Color {
        if isSelected {
            return AlbumListRowStyle.selectionFill
        }
        if isHovered {
            return AlbumListRowStyle.hoverFill
        }
        return .clear
    }
}
