import AppKit
import Combine
import Foundation
import Photos
import SwiftUI

enum MediaGridMoveDirection: Sendable {
    case left, right, up, down
}

@MainActor
final class AppState: ObservableObject {
    let photosService = PhotosService()
    let organizeExporter = OrganizeExporter()

    private var cancellables = Set<AnyCancellable>()
    private var albumLoadGeneration = 0
    private var currentAlbumAssets: [String: PHAsset] = [:]

    @Published var selectedAlbum: PhotoAlbum?
    @Published var mediaItems: [MediaItem] = []
    @Published var isLoadingMedia = false
    @Published var selectedMediaID: String?
    @Published var mediaError: String?
    @Published var quickLookError: String?
    @Published var showOrganizeSheet = false
    @Published var thumbnailDisplayMode: ThumbnailDisplayMode = AppSettings.thumbnailDisplayMode
    @Published var exportDirectoryPath: String? = AppSettings.exportDirectoryPath
    @Published var omittedFromOrganizeAlbumIDs: Set<String> = AppSettings.omittedFromOrganizeAlbumIDs
    @Published var mediaGridColumnCount = AppSettings.mediaGridColumnCount
    @Published var columnVisibility: NavigationSplitViewVisibility = .all

    var selectableAlbums: [PhotoAlbum] {
        photosService.albums.filter { !omittedFromOrganizeAlbumIDs.contains($0.id) }
    }

    init() {
        photosService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        organizeExporter.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        await photosService.requestAuthorization()
    }

    func asset(for item: MediaItem) -> PHAsset? {
        currentAlbumAssets[item.id]
    }

    func selectAlbum(_ album: PhotoAlbum?) async {
        albumLoadGeneration += 1
        let generation = albumLoadGeneration

        selectedMediaID = nil
        mediaError = nil

        guard let album else {
            isLoadingMedia = false
            selectedAlbum = nil
            mediaItems = []
            currentAlbumAssets = [:]
            await ThumbnailLoader.shared.clearMemoryCache()
            return
        }

        isLoadingMedia = true
        selectedAlbum = album
        mediaItems = []
        currentAlbumAssets = [:]

        defer {
            if generation == albumLoadGeneration {
                isLoadingMedia = false
            }
        }

        await ThumbnailLoader.shared.clearMemoryCache(forAlbumID: album.id)

        do {
            let items = try await photosService.mediaItems(for: album)
            guard generation == albumLoadGeneration else { return }
            mediaItems = items
            currentAlbumAssets = PhotosService.buildAssetCache(for: items)
            selectedMediaID = mediaItems.first?.id
        } catch {
            guard generation == albumLoadGeneration else { return }
            mediaError = error.localizedDescription
            mediaItems = []
            currentAlbumAssets = [:]
            selectedMediaID = nil
        }
    }

    func toggleAlbumSelection(_ album: PhotoAlbum) async {
        if selectedAlbum?.id == album.id {
            await selectAlbum(nil)
        } else {
            await selectAlbum(album)
        }
    }

    /// ⌘1–⌘9: select album by index; does not deselect when already selected (use Escape).
    func selectAlbum(at index: Int) async {
        let albums = selectableAlbums
        guard albums.indices.contains(index) else { return }
        let album = albums[index]
        guard selectedAlbum?.id != album.id else { return }
        await selectAlbum(album)
    }

    var canSelectNextAlbum: Bool {
        let albums = selectableAlbums
        guard !albums.isEmpty else { return false }
        guard let selected = selectedAlbum,
              let index = albums.firstIndex(where: { $0.id == selected.id }) else { return true }
        return index < albums.count - 1
    }

    var canSelectPreviousAlbum: Bool {
        let albums = selectableAlbums
        guard !albums.isEmpty else { return false }
        guard let selected = selectedAlbum,
              let index = albums.firstIndex(where: { $0.id == selected.id }) else { return true }
        return index > 0
    }

    func selectNextAlbum() async {
        let albums = selectableAlbums
        guard !albums.isEmpty else { return }

        if let selected = selectedAlbum,
           let index = albums.firstIndex(where: { $0.id == selected.id }),
           index < albums.count - 1 {
            await selectAlbum(albums[index + 1])
        } else {
            await selectAlbum(albums[0])
        }
    }

    func selectPreviousAlbum() async {
        let albums = selectableAlbums
        guard !albums.isEmpty else { return }

        if let selected = selectedAlbum,
           let index = albums.firstIndex(where: { $0.id == selected.id }),
           index > 0 {
            await selectAlbum(albums[index - 1])
        } else {
            await selectAlbum(albums[albums.count - 1])
        }
    }

    func toggleSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.28)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    func toggleThumbnailDisplayMode() {
        withAnimation(.smooth(duration: 0.35)) {
            thumbnailDisplayMode.toggle()
            AppSettings.thumbnailDisplayMode = thumbnailDisplayMode
        }
    }

    func setExportDirectory(_ url: URL) {
        AppSettings.setExportDirectory(url)
        exportDirectoryPath = url.path
    }

    func previewSelectedMedia() async {
        guard let id = selectedMediaID,
              let item = mediaItems.first(where: { $0.id == id }) else { return }
        quickLookError = nil
        do {
            try await QuickLookHelper.preview(item: item, asset: asset(for: item))
        } catch {
            quickLookError = error.localizedDescription
            NSSound.beep()
        }
    }

    var selectedAlbumMediaSummary: String? {
        guard selectedAlbum != nil, !mediaItems.isEmpty else { return nil }
        return MediaSummary.text(for: mediaItems)
    }

    var canDecreaseMediaGridColumnCount: Bool {
        mediaGridColumnCount > AppSettings.mediaGridColumnCountMin
    }

    var canIncreaseMediaGridColumnCount: Bool {
        mediaGridColumnCount < AppSettings.mediaGridColumnCountMax
    }

    func decreaseMediaGridColumnCount() {
        guard canDecreaseMediaGridColumnCount else { return }
        withAnimation(.smooth(duration: 0.4)) {
            mediaGridColumnCount -= 1
            AppSettings.mediaGridColumnCount = mediaGridColumnCount
        }
    }

    func increaseMediaGridColumnCount() {
        guard canIncreaseMediaGridColumnCount else { return }
        withAnimation(.smooth(duration: 0.4)) {
            mediaGridColumnCount += 1
            AppSettings.mediaGridColumnCount = mediaGridColumnCount
        }
    }

    func moveMediaSelection(_ direction: MediaGridMoveDirection) {
        let items = mediaItems
        guard !items.isEmpty else { return }

        let columns = min(
            max(mediaGridColumnCount, AppSettings.mediaGridColumnCountMin),
            AppSettings.mediaGridColumnCountMax
        )
        let currentIndex: Int
        if let selectedMediaID,
           let index = items.firstIndex(where: { $0.id == selectedMediaID }) {
            currentIndex = index
        } else {
            selectedMediaID = items[0].id
            return
        }

        let newIndex: Int
        switch direction {
        case .left:
            newIndex = max(currentIndex - 1, 0)
        case .right:
            newIndex = min(currentIndex + 1, items.count - 1)
        case .up:
            newIndex = max(currentIndex - columns, 0)
        case .down:
            newIndex = min(currentIndex + columns, items.count - 1)
        }

        guard newIndex != currentIndex else { return }
        selectedMediaID = items[newIndex].id
    }

    func isAlbumOmittedFromOrganize(_ album: PhotoAlbum) -> Bool {
        omittedFromOrganizeAlbumIDs.contains(album.id)
    }

    func syncOmittedFromOrganizeAlbums(_ ids: Set<String>) {
        omittedFromOrganizeAlbumIDs = ids
        AppSettings.omittedFromOrganizeAlbumIDs = ids

        guard let selected = selectedAlbum, ids.contains(selected.id) else { return }
        Task { await selectAlbum(nil) }
    }

    var canOrganizeSelectedAlbum: Bool {
        guard let album = selectedAlbum else { return false }
        return photosService.canAccessLibrary && !isAlbumOmittedFromOrganize(album)
    }

    /// Shows the export folder picker, then exports and organizes into the chosen folder.
    func promptExportDirectoryAndOrganize() {
        guard prepareOrganize() else { return }
        guard promptExportDirectory() else { return }
        startOrganize()
    }

    func startOrganize() {
        guard prepareOrganize() else { return }
        guard AppSettings.resolveExportDirectory() != nil else { return }
        showOrganizeSheet = true
        guard let exportURL = AppSettings.resolveExportDirectory(),
              let album = selectedAlbum else { return }

        let sourceAlbumID = album.id
        let assets = currentAlbumAssets
        organizeExporter.organize(
            items: mediaItems,
            assetsByID: assets,
            sourceAlbum: album,
            to: exportURL,
            photosService: photosService
        ) { [weak self] in
            guard let self else { return }
            if selectableAlbums.contains(where: { $0.id == sourceAlbumID }) {
                if let refreshed = selectableAlbums.first(where: { $0.id == sourceAlbumID }) {
                    await selectAlbum(refreshed)
                }
            } else {
                await selectAlbum(nil)
            }
        }
    }

    @discardableResult
    private func prepareOrganize() -> Bool {
        guard let album = selectedAlbum, !isAlbumOmittedFromOrganize(album) else { return false }
        guard photosService.canAccessLibrary else { return false }
        guard !mediaItems.isEmpty else { return false }
        guard !organizeExporter.isRunning else { return false }
        return true
    }

    @discardableResult
    private func promptExportDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Choose the folder where photos and videos from this album will be exported."
        panel.directoryURL = AppSettings.resolveExportDirectory()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        setExportDirectory(url)
        return true
    }
}
