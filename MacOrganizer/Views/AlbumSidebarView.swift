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
        .navigationSplitViewColumnWidth(min: 320, ideal: 340)
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
            List {
                ForEach(Array(appState.selectableAlbums.enumerated()), id: \.element.id) {
                    index, album in
                    Button {
                        Task { await appState.toggleAlbumSelection(album) }
                    } label: {
                        AlbumSidebarRow(album: album, shortcutIndex: index < 9 ? index + 1 : nil)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBackground(for: album))
                }
            }
            .frame(minWidth: 320, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func rowBackground(for album: PhotoAlbum) -> some View {
        if appState.selectedAlbum?.id == album.id {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.2))
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

private struct AlbumSidebarRow: View {
    let album: PhotoAlbum
    let shortcutIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .lineLimit(1)
                Text(album.mediaSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let shortcutIndex {
                Text("\(shortcutIndex)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }
}
