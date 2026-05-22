import AppKit
import Combine
import Foundation
import SwiftUI

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

    var selectableAlbums: [PhotoAlbum] {
        let albums = photosService.albums
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
        await selectAlbum(albums[index])
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

    func toggleThumbnailDisplayMode() {
        thumbnailDisplayMode.toggle()
        AppSettings.thumbnailDisplayMode = thumbnailDisplayMode
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func startOrganize() {
        guard selectedAlbum != nil, !mediaItems.isEmpty else { return }
        guard AppSettings.resolveExportDirectory() != nil else { return }
        showOrganizeSheet = true
        guard let exportURL = AppSettings.resolveExportDirectory() else { return }
        organizeExporter.organize(items: mediaItems, to: exportURL)
    }
}
