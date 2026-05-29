import AppKit
import Photos
import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isGridFocused: Bool

    private let cellSpacing: CGFloat = 2
    private let gridEdgeInset: CGFloat = 8

    var body: some View {
        gridContent
            .padding(.leading, gridEdgeInset)
            .padding(.top, gridEdgeInset)
            .onChange(of: appState.selectedAlbum?.id) { _, _ in
                isGridFocused = false
            }
            .onChange(of: appState.isLoadingMedia) { _, isLoading in
                guard !isLoading,
                      appState.selectedAlbum != nil,
                      appState.selectedMediaID != nil else { return }
                isGridFocused = true
            }
            .background {
                AlbumNumberKeyboardShortcuts()
            }
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
                            assetForItem: { appState.asset(for: $0) },
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
                    .onKeyPress(.escape) {
                        appState.photosEscapeBack()
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
            .id(appState.selectedAlbum?.id)
        }
    }

}

private struct MediaThumbnailCell: View {
    let item: MediaItem
    let album: PhotoAlbum
    let isSelected: Bool
    let displayMode: ThumbnailDisplayMode
    let cellSize: CGFloat
    let asset: PHAsset?

    @State private var image: NSImage?
    @State private var loadFailed = false
    @State private var loadGeneration = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(cellBackground)

            if let image {
                thumbnailImage(image)
            } else if loadFailed {
                VStack(spacing: 4) {
                    Image(systemName: item.isVideo ? "video" : "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        retryLoad()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private var accessibilityLabel: String {
        let kind = item.isVideo ? "Video" : "Photo"
        return "\(kind), \(item.filename)"
    }

    private func retryLoad() {
        loadFailed = false
        image = nil
        loadGeneration += 1
        let generation = loadGeneration
        Task {
            await loadThumbnail(generation: generation)
        }
    }

    private func loadThumbnail(generation: Int? = nil) async {
        let activeGeneration = generation ?? loadGeneration
        loadFailed = false
        if let cached = await ThumbnailLoader.shared.cachedImage(for: item.id) {
            guard activeGeneration == loadGeneration else { return }
            image = cached
            return
        }
        let loaded = await ThumbnailLoader.shared.thumbnail(for: item, album: album, asset: asset)
        guard activeGeneration == loadGeneration else { return }
        image = loaded
        loadFailed = loaded == nil
    }

    private var cellBackground: Color {
        switch displayMode {
        case .square:
            Color.black
        case .fit:
            Color.clear
        }
    }

    @ViewBuilder
    private func thumbnailImage(_ image: NSImage) -> some View {
        let dimensions = displayedImageDimensions(for: image)
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: displayMode == .square ? .fill : .fit)
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
    let assetForItem: (MediaItem) -> PHAsset?
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
                        Button {
                            onSelect(item.id)
                        } label: {
                            MediaThumbnailCell(
                                item: item,
                                album: selectedAlbum,
                                isSelected: selectedMediaID == item.id,
                                displayMode: displayMode,
                                cellSize: cellSize,
                                asset: assetForItem(item)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
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
