import AppKit
import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isGridFocused: Bool

    private let cellSpacing: CGFloat = 2

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            gridContent
        }
        .onExitCommand {
            QuickLookHelper.closePreview()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if let album = appState.selectedAlbum {
                VStack(alignment: .leading, spacing: AlbumListRowStyle.labelSpacing) {
                    Text(album.name)
                        .font(AlbumListRowStyle.toolbarTitleFont)
                    Text(album.mediaSummary)
                        .font(AlbumListRowStyle.detailFont)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let path = appState.exportDirectoryPath {
                Text(path)
                    .font(AlbumListRowStyle.detailFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            } else {
                Text("No export folder")
                    .font(AlbumListRowStyle.detailFont)
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
            .disabled(
                appState.selectedAlbum == nil
                    || appState.mediaItems.isEmpty
                    || appState.organizeExporter.isRunning
                    || !appState.canOrganizeSelectedAlbum
            )
            .help(
                appState.canOrganizeSelectedAlbum
                    ? "Copy album media to the export folder"
                    : "This album is omitted from Organize in Settings"
            )
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
                ScrollViewReader { proxy in
                    ScrollView {
                        SmoothMediaGrid(
                            columnCount: CGFloat(appState.mediaGridColumnCount),
                            availableWidth: geometry.size.width,
                            spacing: cellSpacing,
                            items: appState.mediaItems,
                            selectedAlbum: appState.selectedAlbum!,
                            selectedMediaID: appState.selectedMediaID,
                            displayMode: appState.thumbnailDisplayMode,
                            onSelect: { itemID in
                                appState.selectedMediaID = itemID
                                isGridFocused = true
                            }
                        )
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
        .modifier(AnimatableCellSize(size: cellSize))
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

/// Lazy row grid with animatable column count and cell size for smooth +/- transitions.
private struct SmoothMediaGrid: View, Animatable {
    var columnCount: CGFloat
    var availableWidth: CGFloat
    let spacing: CGFloat
    let items: [MediaItem]
    let selectedAlbum: PhotoAlbum
    let selectedMediaID: String?
    let displayMode: ThumbnailDisplayMode
    let onSelect: (String) -> Void

    var animatableData: CGFloat {
        get { columnCount }
        set { columnCount = newValue }
    }

    private var clampedColumnCount: CGFloat {
        min(
            max(columnCount, CGFloat(AppSettings.mediaGridColumnCountMin)),
            CGFloat(AppSettings.mediaGridColumnCountMax)
        )
    }

    private var layoutColumnCount: Int {
        Int(round(clampedColumnCount))
    }

    private var cellSize: CGFloat {
        let available = max(availableWidth - spacing * 2, 1)
        return (available - spacing * (clampedColumnCount - 1)) / clampedColumnCount
    }

    private var rowCount: Int {
        guard layoutColumnCount > 0 else { return 0 }
        return (items.count + layoutColumnCount - 1) / layoutColumnCount
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(itemsInRow(row)) { item in
                        MediaThumbnailCell(
                            item: item,
                            album: selectedAlbum,
                            isSelected: selectedMediaID == item.id,
                            displayMode: displayMode,
                            cellSize: cellSize
                        )
                        .id(item.id)
                        .onTapGesture {
                            onSelect(item.id)
                        }
                    }

                    if itemsInRow(row).count < layoutColumnCount {
                        ForEach(0..<(layoutColumnCount - itemsInRow(row).count), id: \.self) { _ in
                            Color.clear
                                .modifier(AnimatableCellSize(size: cellSize))
                        }
                    }
                }
            }
        }
        .padding(spacing)
    }

    private func itemsInRow(_ row: Int) -> [MediaItem] {
        let start = row * layoutColumnCount
        let end = min(start + layoutColumnCount, items.count)
        guard start < end else { return [] }
        return Array(items[start..<end])
    }
}

private struct AnimatableCellSize: AnimatableModifier {
    var size: CGFloat

    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content.frame(width: size, height: size)
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
