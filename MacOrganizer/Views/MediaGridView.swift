import AppKit
import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var appState: AppState
    @State private var columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            gridContent
        }
        .onChange(of: appState.selectedMediaID) { _, newID in
            guard let newID, let item = appState.mediaItems.first(where: { $0.id == newID }) else { return }
            Task { await QuickLookHelper.preview(item: item) }
        }
        .onExitCommand {
            QuickLookHelper.closePreview()
        }
        .background {
            Button("") {
                guard let id = appState.selectedMediaID,
                      let item = appState.mediaItems.first(where: { $0.id == id }) else { return }
                Task { await QuickLookHelper.preview(item: item) }
            }
            .keyboardShortcut(.space, modifiers: [])
            .hidden()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if let album = appState.selectedAlbum {
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.headline)
                    Text(album.mediaSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let path = AppSettings.exportDirectoryPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            } else {
                Text("No export folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Choose Folder…") {
                chooseExportDirectory()
            }

            Button("Organize") {
                if AppSettings.resolveExportDirectory() == nil {
                    chooseExportDirectory(thenOrganize: true)
                } else {
                    appState.startOrganize()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.selectedAlbum == nil || appState.mediaItems.isEmpty || appState.organizeExporter.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var gridContent: some View {
        if appState.isLoadingMedia {
            ProgressView("Loading media…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appState.mediaError {
            ContentUnavailableView("Could Not Load Media", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if appState.mediaItems.isEmpty {
            ContentUnavailableView("No Media", systemImage: "photo", description: Text("This album has no photos or videos."))
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(appState.mediaItems) { item in
                        MediaThumbnailCell(
                            item: item,
                            album: appState.selectedAlbum!,
                            isSelected: appState.selectedMediaID == item.id
                        )
                        .onTapGesture {
                            appState.selectedMediaID = item.id
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func chooseExportDirectory(thenOrganize: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Export Folder"
        panel.message = "Photos and videos will be copied into this folder when you organize."

        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.setExportDirectory(url)
            if thenOrganize {
                appState.startOrganize()
            }
        }
    }
}

private struct MediaThumbnailCell: View {
    let item: MediaItem
    let album: PhotoAlbum
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .aspectRatio(1, contentMode: .fit)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if loadFailed {
                    Image(systemName: item.isVideo ? "video" : "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.35))
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }

            Text(item.filename)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.id) {
            loadFailed = false
            image = await ThumbnailLoader.shared.thumbnail(for: item, album: album)
            if image == nil {
                loadFailed = true
            }
        }
    }
}
