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
        .navigationTitle(mainToolbarTitle)
        .toolbar {
            if let album = appState.selectedAlbum {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: .leading, spacing: AlbumListRowStyle.labelSpacing) {
                        Text(album.name)
                            .font(AlbumListRowStyle.toolbarTitleFont)
                        Text(album.mediaSummary)
                            .font(AlbumListRowStyle.detailFont)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

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

            if appState.selectedAlbum != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Organize") {
                        appState.promptExportDirectoryAndOrganize()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        appState.mediaItems.isEmpty
                            || appState.organizeExporter.isRunning
                            || !appState.canOrganizeSelectedAlbum
                    )
                    .keyboardShortcut("e", modifiers: .command)
                    .help(
                        appState.canOrganizeSelectedAlbum
                            ? "Export, move to album with suffix, and remove from source (⌘E)"
                            : "This album is omitted from Organize in Settings"
                    )
                }
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

    private var mainToolbarTitle: String {
        appState.selectedAlbum == nil ? "iCloud Photos Organizer" : ""
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
