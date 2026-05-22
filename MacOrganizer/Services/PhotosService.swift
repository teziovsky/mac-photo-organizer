import Foundation
import Photos

enum PhotosAuthorizationState: Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

enum PhotosServiceError: LocalizedError, Sendable {
    case accessDenied
    case albumNotFound(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photos library access was denied. Grant access in System Settings → Privacy & Security → Photos."
        case .albumNotFound(let name):
            return "Album \"\(name)\" was not found in Photos."
        }
    }
}

@MainActor
final class PhotosService: ObservableObject {
    @Published private(set) var authorizationState: PhotosAuthorizationState = .notDetermined
    @Published private(set) var albums: [PhotoAlbum] = []
    @Published private(set) var isLoadingAlbums = false
    @Published var errorMessage: String?

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationState = mapStatus(status)
        guard authorizationState == .authorized else { return }
        await reloadAlbums()
    }

    func reloadAlbums() async {
        guard authorizationState == .authorized else { return }
        isLoadingAlbums = true
        errorMessage = nil
        defer { isLoadingAlbums = false }

        let excludedSuffix = AppSettings.excludedAlbumSuffix
        albums = await Task.detached(priority: .userInitiated) {
            Self.collectAlbums(excludedSuffix: excludedSuffix)
        }.value
    }

    func mediaItems(for album: PhotoAlbum) async throws -> [MediaItem] {
        guard authorizationState == .authorized else { throw PhotosServiceError.accessDenied }
        guard let collection = Self.fetchCollection(identifier: album.collectionIdentifier) else {
            throw PhotosServiceError.albumNotFound(album.name)
        }
        return await Task.detached(priority: .userInitiated) {
            Self.fetchMediaItems(in: collection)
        }.value
    }

    func asset(for item: MediaItem) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [item.id], options: nil).firstObject
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotosAuthorizationState {
        switch status {
        case .authorized, .limited:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    nonisolated private static func collectAlbums(excludedSuffix: String) -> [PhotoAlbum] {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        var results: [PhotoAlbum] = []
        results.reserveCapacity(collections.count)

        var index = 0
        while index < collections.count {
            let album = collections.object(at: index)
            if let photoAlbum = makePhotoAlbum(from: album, excludedSuffix: excludedSuffix) {
                results.append(photoAlbum)
            }
            index += 1
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated private static func isSharedAlbum(_ album: PHAssetCollection) -> Bool {
        switch album.assetCollectionSubtype {
        case .albumCloudShared, .albumMyPhotoStream:
            return true
        default:
            return false
        }
    }

    nonisolated private static func makePhotoAlbum(
        from album: PHAssetCollection,
        excludedSuffix: String
    ) -> PhotoAlbum? {
        guard !isSharedAlbum(album) else { return nil }

        let name = album.localizedTitle ?? "Untitled"
        guard AlbumNameFilter.shouldInclude(albumName: name, excludedSuffix: excludedSuffix) else { return nil }

        let assets = PHAsset.fetchAssets(in: album, options: nil)
        let mediaCount = assets.count
        guard mediaCount > 0 else { return nil }

        var videoCount = 0
        var assetIndex = 0
        while assetIndex < assets.count {
            if assets.object(at: assetIndex).mediaType == .video {
                videoCount += 1
            }
            assetIndex += 1
        }

        return PhotoAlbum(
            id: album.localIdentifier,
            name: name,
            mediaCount: mediaCount,
            photoCount: mediaCount - videoCount,
            videoCount: videoCount,
            collectionIdentifier: album.localIdentifier
        )
    }

    nonisolated private static func fetchCollection(identifier: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
    }

    nonisolated private static func fetchMediaItems(in collection: PHAssetCollection) -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        var items: [MediaItem] = []
        items.reserveCapacity(assets.count)

        var index = 0
        while index < assets.count {
            let asset = assets.object(at: index)
            items.append(
                MediaItem(
                    id: asset.localIdentifier,
                    filename: Self.filename(for: asset),
                    isVideo: asset.mediaType == .video,
                    creationDate: asset.creationDate
                )
            )
            index += 1
        }
        return items
    }

    nonisolated private static func filename(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        if let original = resources.first(where: { $0.type == .photo || $0.type == .video || $0.type == .fullSizeVideo }) {
            return original.originalFilename
        }
        let ext = asset.mediaType == .video ? "mov" : "jpg"
        return "\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_")).\(ext)"
    }
}
