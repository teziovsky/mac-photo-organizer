import AppKit
import Combine
import Foundation
import SwiftUI

enum MediaGridMoveDirection: Sendable {
    case left, right, up, down
}

@MainActor
final class AppState: ObservableObject {
    let photosService = PhotosService()
    let organizeExporter = OrganizeExporter()

    private var cancellables = Set<AnyCancellable>()

    @Published var selectedAlbum: PhotoAlbum?
    @Published var mediaItems: [MediaItem] = []
    @Published var isLoadingMedia = false
    @Published var selectedMediaID: String?
    @Published var mediaError: String?
    @Published var showOrganizeSheet = false
    @Published var thumbnailDisplayMode: ThumbnailDisplayMode = AppSettings.thumbnailDisplayMode
    @Published var albumSearchText = ""
    @Published var isAlbumSearchFocused = false
    @Published var exportDirectoryPath: String? = AppSettings.exportDirectoryPath
    @Published var omittedFromOrganizeAlbumIDs: Set<String> = AppSettings.omittedFromOrganizeAlbumIDs
    @Published var mediaGridColumnCount = AppSettings.mediaGridColumnCount
    @Published var columnVisibility: NavigationSplitViewVisibility = .all

    var selectableAlbums: [PhotoAlbum] {
        let albums = photosService.albums.filter { !omittedFromOrganizeAlbumIDs.contains($0.id) }
        let query = albumSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return albums }
        return albums.filter { $0.name.localizedCaseInsensitiveContains(query) }
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

    func selectAlbum(_ album: PhotoAlbum?) async {
        selectedMediaID = nil
        mediaError = nil

        guard let album else {
            isLoadingMedia = false
            selectedAlbum = nil
            mediaItems = []
            await ThumbnailLoader.shared.clearMemoryCache()
            return
        }

        isLoadingMedia = true
        selectedAlbum = album
        mediaItems = []

        defer { isLoadingMedia = false }

        await ThumbnailLoader.shared.clearMemoryCache()

        do {
            mediaItems = try await photosService.mediaItems(for: album)
        } catch {
            mediaError = error.localizedDescription
            mediaItems = []
        }
    }

    func toggleAlbumSelection(_ album: PhotoAlbum) async {
        if selectedAlbum?.id == album.id {
            await selectAlbum(nil)
        } else {
            await selectAlbum(album)
        }
    }

    func selectAlbum(at index: Int) async {
        let albums = selectableAlbums
        guard albums.indices.contains(index) else { return }
        await toggleAlbumSelection(albums[index])
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

    func focusAlbumSearch() {
        isAlbumSearchFocused = true
        AlbumSearchFocus.focusAndSelectAll()
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
        await QuickLookHelper.preview(item: item)
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
        return !isAlbumOmittedFromOrganize(album)
    }

    func startOrganize() {
        guard let album = selectedAlbum, !isAlbumOmittedFromOrganize(album) else { return }
        guard !mediaItems.isEmpty else { return }
        guard !organizeExporter.isRunning else { return }
        guard AppSettings.resolveExportDirectory() != nil else { return }
        showOrganizeSheet = true
        guard let exportURL = AppSettings.resolveExportDirectory() else { return }

        let sourceAlbumID = album.id
        organizeExporter.organize(
            items: mediaItems,
            sourceAlbum: album,
            to: exportURL,
            photosService: photosService
        ) { [weak self] in
            guard let self else { return }
            await photosService.reloadAlbums()
            if selectableAlbums.contains(where: { $0.id == sourceAlbumID }) {
                if let refreshed = selectableAlbums.first(where: { $0.id == sourceAlbumID }) {
                    await selectAlbum(refreshed)
                }
            } else {
                await selectAlbum(nil)
            }
        }
    }
}
