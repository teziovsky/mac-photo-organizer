import SwiftUI

struct AlbumSidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var filteredAlbums: [PhotoAlbum] {
        let albums = appState.photosService.albums
        guard !searchText.isEmpty else { return albums }
        return albums.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

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
                        "Allow Mac Organizer to access your Photos library in System Settings.")
                )
            }
        }
        .frame(minWidth: 320, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 320, ideal: 340)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gear")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await appState.photosService.reloadAlbums() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.photosService.isLoadingAlbums)
            }
        }
        .searchable(text: $searchText, prompt: "Search albums")
        .overlay {
            if appState.photosService.isLoadingAlbums {
                ProgressView()
                    .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var albumList: some View {
        if filteredAlbums.isEmpty && !appState.photosService.isLoadingAlbums {
            ContentUnavailableView(
                "No Albums",
                systemImage: "folder",
                description: Text(emptyAlbumsDescription)
            )
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(
                selection: Binding(
                    get: { appState.selectedAlbum?.id },
                    set: { newID in
                        guard let newID else {
                            Task { await appState.selectAlbum(nil) }
                            return
                        }
                        guard let album = filteredAlbums.first(where: { $0.id == newID }) else {
                            return
                        }
                        Task { await appState.selectAlbum(album) }
                    }
                )
            ) {
                ForEach(filteredAlbums) { album in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album.name)
                            .lineLimit(1)
                        Text(album.mediaSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(album.id)
                }
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
