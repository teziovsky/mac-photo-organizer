import AppKit
import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isGridFocused: Bool

    private let cellSpacing: CGFloat = 2
    private let minimumCellSize: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            gridContent
        }
        .onExitCommand {
            QuickLookHelper.closePreview()
        }
        .background {
            Button("") {
                Task { await appState.previewSelectedMedia() }
            }
            .keyboardShortcut("y", modifiers: .command)
            .hidden()
            .disabled(appState.selectedMediaID == nil)
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

            if let path = appState.exportDirectoryPath {
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
            GeometryReader { geometry in
                let layout = gridLayout(for: geometry.size.width)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: layout.columns, spacing: cellSpacing) {
                            ForEach(appState.mediaItems) { item in
                                MediaThumbnailCell(
                                    item: item,
                                    album: appState.selectedAlbum!,
                                    isSelected: appState.selectedMediaID == item.id,
                                    displayMode: appState.thumbnailDisplayMode,
                                    cellSize: layout.cellSize
                                )
                                .id(item.id)
                                .onTapGesture {
                                    appState.selectedMediaID = item.id
                                    isGridFocused = true
                                }
                            }
                        }
                        .padding(cellSpacing)
                        .animation(.smooth(duration: 0.35), value: appState.thumbnailDisplayMode)
                    }
                    .focusable()
                    .focused($isGridFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.leftArrow) {
                        appState.moveMediaSelection(.left)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        appState.moveMediaSelection(.right)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        appState.moveMediaSelection(.up)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        appState.moveMediaSelection(.down)
                        return .handled
                    }
                    .onAppear {
                        appState.updateMediaGridColumnCount(layout.columnCount)
                    }
                    .onChange(of: geometry.size.width) { _, width in
                        appState.updateMediaGridColumnCount(gridLayout(for: width).columnCount)
                    }
                    .onChange(of: appState.selectedMediaID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
            .background(Color.black.opacity(0.92))
            .id(appState.selectedAlbum?.id)
            .onAppear { isGridFocused = true }
        }
    }

    private func gridLayout(for width: CGFloat) -> (columns: [GridItem], cellSize: CGFloat, columnCount: Int) {
        let availableWidth = max(width - cellSpacing * 2, minimumCellSize)
        let columnCount = max(1, Int((availableWidth + cellSpacing) / (minimumCellSize + cellSpacing)))
        let cellSize = (availableWidth - cellSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: cellSpacing), count: columnCount)
        return (columns, cellSize, columnCount)
    }

    private func chooseExportDirectory(thenOrganize: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Export Folder"
        panel.message = "Photos and videos will be copied into this folder when you organize."

        if panel.runModal() == .OK, let url = panel.url {
            appState.setExportDirectory(url)
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
    let displayMode: ThumbnailDisplayMode
    let cellSize: CGFloat

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)

            if let image {
                thumbnailImage(image)
            } else if loadFailed {
                Image(systemName: item.isVideo ? "video" : "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .overlay {
            Rectangle()
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        }
        .contentShape(Rectangle())
        .task(id: item.id) {
            loadFailed = false
            if let cached = await ThumbnailLoader.shared.cachedImage(for: item.id) {
                image = cached
                return
            }
            image = await ThumbnailLoader.shared.thumbnail(for: item, album: album)
            if image == nil {
                loadFailed = true
            }
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ image: NSImage) -> some View {
        let dimensions = displayedImageDimensions(for: image)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .modifier(AnimatableThumbnailFrame(width: dimensions.width, height: dimensions.height))
            .clipShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo {
                    videoPlayIndicator
                        .transition(.opacity)
                }
            }
    }

    private var videoPlayIndicator: some View {
        Image(systemName: "play.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.35))
            .padding(6)
    }

    private func displayedImageDimensions(for image: NSImage) -> CGSize {
        if displayMode == .square {
            return CGSize(width: cellSize, height: cellSize)
        }

        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else {
            return CGSize(width: cellSize, height: cellSize)
        }

        let aspect = width / height
        if aspect >= 1 {
            return CGSize(width: cellSize, height: cellSize / aspect)
        }
        return CGSize(width: cellSize * aspect, height: cellSize)
    }
}

private struct AnimatableThumbnailFrame: AnimatableModifier {
    var width: CGFloat
    var height: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set {
            width = newValue.first
            height = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.frame(width: width, height: height)
    }
}
