import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            AlbumSidebarView()
        } detail: {
            if appState.selectedAlbum != nil {
                MediaGridView()
            } else {
                ContentUnavailableView(
                    "Select an Album",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(
                        "Choose an album from the sidebar to review photos before organizing.")
                )
            }
        }
        .navigationTitle("Mac Organizer")
        .searchable(text: $appState.albumSearchText, prompt: "Search albums")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if appState.selectedAlbum != nil {
                    Button {
                        Task { await appState.selectAlbum(nil) }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Deselect album")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.toggleThumbnailDisplayMode()
                } label: {
                    Label(
                        appState.thumbnailDisplayMode.toolbarLabel,
                        systemImage: appState.thumbnailDisplayMode.toolbarIcon
                    )
                }
                .help("Toggle square cropped or full aspect ratio thumbnails")

                Button {
                    Task { await appState.photosService.reloadAlbums() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.photosService.isLoadingAlbums)
            }
        }
        .sheet(isPresented: $appState.showOrganizeSheet) {
            OrganizeProgressView()
                .environmentObject(appState)
        }
    }
}
