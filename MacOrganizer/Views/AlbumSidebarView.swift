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
        .frame(minWidth: 280, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 260, ideal: 280)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: AlbumListRowStyle.sidebarRowSpacing) {
                    ForEach(appState.selectableAlbums) { album in
                        AlbumSidebarListRow(
                            album: album,
                            isSelected: appState.selectedAlbum?.id == album.id
                        ) {
                            Task { await appState.toggleAlbumSelection(album) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AlbumListRowStyle.sidebarListInset)
                .padding(.vertical, AlbumListRowStyle.sidebarListInset)
            }
            .frame(maxHeight: .infinity)
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
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        AlbumSidebarRowContent(album: album)
            .albumSidebarRowChrome(backgroundFill: rowBackgroundFill)
            .onTapGesture(perform: onSelect)
            .onHover { isHovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private var rowBackgroundFill: Color {
        if isSelected {
            return AlbumListRowStyle.sidebarSelectionFill
        }
        if isHovered {
            return AlbumListRowStyle.sidebarHoverFill
        }
        return .clear
    }
}
