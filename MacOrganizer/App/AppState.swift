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
        selectedAlbum = album
        selectedMediaID = nil
        mediaItems = []
        mediaError = nil
        await ThumbnailLoader.shared.clearMemoryCache()

        guard let album else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false }

        do {
            mediaItems = try await photosService.mediaItems(for: album)
        } catch {
            mediaError = error.localizedDescription
        }
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
