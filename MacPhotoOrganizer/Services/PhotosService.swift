import Foundation
import Photos

enum PhotosAuthorizationState: Sendable {
    case authorized
    case limited
    case denied
    case restricted
    case notDetermined
}

enum PhotosServiceError: LocalizedError, Sendable {
    case accessDenied
    case limitedAccess
    case albumNotFound(String)
    case organizeFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photos library access was denied. Grant access in System Settings → Privacy & Security → Photos."
        case .limitedAccess:
            return "Full Photos library access is required to browse albums and organize. Grant full access in System Settings → Privacy & Security → Photos."
        case .albumNotFound(let name):
            return "Album \"\(name)\" was not found in Photos."
        case .organizeFailed(let message):
            return message
        }
    }
}

@MainActor
final class PhotosService: NSObject, ObservableObject {
    @Published private(set) var authorizationState: PhotosAuthorizationState = .notDetermined
    @Published private(set) var albums: [PhotoAlbum] = []
    @Published private(set) var isLoadingAlbums = false
    @Published var errorMessage: String?

    private var changeObserverRegistered = false
    private var deferAlbumReloadFromLibraryChanges = false

    override init() {
        super.init()
        authorizationState = mapStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        registerChangeObserverIfNeeded()
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationState = mapStatus(status)
        registerChangeObserverIfNeeded()
        guard canAccessLibrary else { return }
        await reloadAlbums()
    }

    var canAccessLibrary: Bool {
        authorizationState == .authorized
    }

    func reloadAlbums() async {
        guard canAccessLibrary else { return }
        isLoadingAlbums = true
        errorMessage = nil
        defer { isLoadingAlbums = false }

        let excludedSuffix = AppSettings.excludedAlbumSuffix
        albums = await Task.detached(priority: .userInitiated) {
            Self.collectAlbums(excludedSuffix: excludedSuffix)
        }.value
    }

    /// Coalesces `photoLibraryDidChange` reloads while Organize is moving assets (one refresh at `endDeferringAlbumReloadFromLibraryChanges`).
    func beginDeferringAlbumReloadFromLibraryChanges() {
        deferAlbumReloadFromLibraryChanges = true
    }

    func endDeferringAlbumReloadFromLibraryChanges() async {
        deferAlbumReloadFromLibraryChanges = false
        await reloadAlbums()
    }

    func mediaItems(for album: PhotoAlbum) async throws -> [MediaItem] {
        guard canAccessLibrary else {
            if authorizationState == .limited {
                throw PhotosServiceError.limitedAccess
            }
            throw PhotosServiceError.accessDenied
        }
        guard let collection = Self.fetchCollection(identifier: album.collectionIdentifier) else {
            throw PhotosServiceError.albumNotFound(album.name)
        }
        return await Task.detached(priority: .userInitiated) {
            Self.fetchMediaItems(in: collection)
        }.value
    }

    static func buildAssetCache(for items: [MediaItem]) -> [String: PHAsset] {
        guard !items.isEmpty else { return [:] }
        let ids = items.map(\.id)
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var cache: [String: PHAsset] = [:]
        cache.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            cache[asset.localIdentifier] = asset
        }
        return cache
    }

    static func destinationAlbumTitle(forSourceAlbumNamed sourceName: String) -> String {
        let suffix = AppSettings.excludedAlbumSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceName + suffix
    }

    func moveAsset(
        _ asset: PHAsset,
        fromSourceAlbum sourceAlbum: PhotoAlbum,
        toAlbumNamed targetTitle: String
    ) async throws {
        guard canAccessLibrary else {
            if authorizationState == .limited {
                throw PhotosServiceError.limitedAccess
            }
            throw PhotosServiceError.accessDenied
        }
        guard targetTitle != sourceAlbum.name else {
            throw PhotosServiceError.organizeFailed("Destination album name matches the source album.")
        }
        guard let sourceCollection = Self.fetchCollection(identifier: sourceAlbum.collectionIdentifier) else {
            throw PhotosServiceError.albumNotFound(sourceAlbum.name)
        }

        try await Self.performMove(
            asset: asset,
            sourceCollection: sourceCollection,
            targetAlbumTitle: targetTitle
        )
    }

    private func registerChangeObserverIfNeeded() {
        guard canAccessLibrary, !changeObserverRegistered else { return }
        PHPhotoLibrary.shared().register(self)
        changeObserverRegistered = true
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotosAuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .limited:
            return .limited
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

        return PhotoAlbum(
            id: album.localIdentifier,
            name: name,
            mediaCount: mediaCount,
            photoCount: mediaCount,
            videoCount: 0,
            collectionIdentifier: album.localIdentifier
        )
    }

    nonisolated private static func fetchCollection(identifier: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [identifier],
            options: nil
        ).firstObject
    }

    nonisolated private static func fetchCollection(title: String) -> PHAssetCollection? {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: nil
        )
        var index = 0
        while index < collections.count {
            let collection = collections.object(at: index)
            if collection.localizedTitle == title {
                return collection
            }
            index += 1
        }
        return nil
    }

    nonisolated private static func performMove(
        asset: PHAsset,
        sourceCollection: PHAssetCollection,
        targetAlbumTitle: String
    ) async throws {
        let targetCollection: PHAssetCollection
        if let existing = fetchCollection(title: targetAlbumTitle) {
            targetCollection = existing
        } else {
            targetCollection = try await createAlbum(title: targetAlbumTitle)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: targetCollection)?
                    .addAssets([asset] as NSArray)
                PHAssetCollectionChangeRequest(for: sourceCollection)?
                    .removeAssets([asset] as NSArray)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: PhotosServiceError.organizeFailed("Photos could not update albums.")
                    )
                }
            }
        }
    }

    nonisolated private static func createAlbum(title: String) async throws -> PHAssetCollection {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PHAssetCollection, Error>) in
            var createdIdentifier: String?
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                createdIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard success,
                      let createdIdentifier,
                      let collection = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [createdIdentifier],
                        options: nil
                      ).firstObject else {
                    continuation.resume(
                        throwing: PhotosServiceError.organizeFailed("Could not create album \"\(title)\".")
                    )
                    return
                }
                continuation.resume(returning: collection)
            }
        }
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
            return SafeFilename.sanitize(original.originalFilename, fallback: "photo")
        }
        let ext = asset.mediaType == .video ? "mov" : "jpg"
        return SafeFilename.sanitize(
            "\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_")).\(ext)",
            fallback: "photo.\(ext)"
        )
    }
}

extension PhotosService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard canAccessLibrary else { return }
            guard !deferAlbumReloadFromLibraryChanges else { return }
            guard !isLoadingAlbums else { return }
            await reloadAlbums()
        }
    }
}
