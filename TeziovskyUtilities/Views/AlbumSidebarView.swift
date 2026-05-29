import SwiftUI

struct AlbumSidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.photosService.authorizationState {
            case .notDetermined:
                AlbumsLoadingView(message: "Connecting to Photos…")
            case .authorized:
                albumList
            case .limited:
                PhotosLimitedAccessView()
            case .denied, .restricted:
                PhotosAccessUnavailableView(
                    title: "Photos Access Required",
                    description: "Allow \(AppBranding.appName) to access your Photos library in System Settings."
                )
            }
        }
        .frame(minWidth: 280, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 260, ideal: 280)
        .overlay(alignment: .top) {
            if let error = appState.photosService.errorMessage {
                Text(error)
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    private var albumList: some View {
        if appState.photosService.isLoadingAlbums && appState.selectableAlbums.isEmpty {
            AlbumsLoadingView()
        } else if appState.selectableAlbums.isEmpty {
            let message = OrganizeCompleteMessaging.sidebar(
                allAlbums: appState.photosService.albums,
                selectableAlbums: appState.selectableAlbums
            )
            OrganizeCompleteEmptyView(title: message.title, description: message.description)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AlbumListRowStyle.sidebarRowSpacing) {
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
            .overlay {
                if appState.photosService.isLoadingAlbums {
                    ZStack {
                        Color.clear
                        ProgressView()
                            .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        }
    }

}

private struct AlbumSidebarListRow: View {
    let album: PhotoAlbum
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            AlbumSidebarRowContent(album: album)
                .albumSidebarRowChrome(backgroundFill: rowBackgroundFill)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(album.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("\(album.mediaCount) items")
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
