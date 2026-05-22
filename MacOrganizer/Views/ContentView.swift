import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView(columnVisibility: $appState.columnVisibility) {
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
        .onExitCommand(perform: handleEscape)
        .navigationTitle("iCloud Photos Organizer")
        .searchable(
            text: $appState.albumSearchText,
            isPresented: $appState.isAlbumSearchFocused,
            prompt: "Search albums"
        )
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
            if appState.selectedAlbum != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        appState.decreaseMediaGridColumnCount()
                    } label: {
                        Label("Larger Thumbnails", systemImage: "plus")
                    }
                    .help("Fewer columns, larger thumbnails (⌘+)")
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!appState.canDecreaseMediaGridColumnCount)

                    Button {
                        appState.increaseMediaGridColumnCount()
                    } label: {
                        Label("Smaller Thumbnails", systemImage: "minus")
                    }
                    .help("More columns, smaller thumbnails (⌘−)")
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!appState.canIncreaseMediaGridColumnCount)
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
                .help("Toggle square cropped or full aspect ratio thumbnails (⌘T)")
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.selectedAlbum == nil)

                Button {
                    Task { await appState.photosService.reloadAlbums() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload albums from Photos (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.photosService.isLoadingAlbums)
            }
        }
        .sheet(isPresented: $appState.showOrganizeSheet) {
            OrganizeProgressView()
                .environmentObject(appState)
        }
        .background {
            MainWindowKeyboardShortcuts()
            if appState.selectedAlbum == nil {
                AlbumNumberKeyboardShortcuts()
            }
        }
    }

    private func handleEscape() {
        if QuickLookHelper.isPanelVisible {
            QuickLookHelper.closePreview()
            return
        }
        guard appState.selectedAlbum != nil else { return }
        Task { await appState.selectAlbum(nil) }
    }
}
