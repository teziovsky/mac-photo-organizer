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
        .sheet(isPresented: $appState.showOrganizeSheet) {
            OrganizeProgressView()
                .environmentObject(appState)
        }
        .navigationTitle("Mac Organizer")
    }
}
