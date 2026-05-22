import AppKit
import CryptoKit
import Foundation
import Photos

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let imageManager = PHImageManager.default()
    private var memoryCache: [String: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 400, height: 400)

    private var cacheRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MacOrganizer/Thumbnails", isDirectory: true)
    }

    func thumbnail(for item: MediaItem, album: PhotoAlbum) async -> NSImage? {
        if let cached = memoryCache[item.id] {
            return cached
        }

        let diskPath = diskCacheURL(album: album, itemID: item.id)
        if FileManager.default.fileExists(atPath: diskPath.path),
           let image = NSImage(contentsOf: diskPath) {
            memoryCache[item.id] = image
            return image
        }

        guard let asset = item.asset else { return nil }

        let image = await requestImage(for: asset)
        guard let image else { return nil }

        memoryCache[item.id] = image
        try? saveToDisk(image: image, url: diskPath)
        return image
    }

    func clearMemoryCache() {
        memoryCache.removeAll()
    }

    private func requestImage(for asset: PHAsset) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private func diskCacheURL(album: PhotoAlbum, itemID: String) -> URL {
        let albumHash = SHA256.hash(data: Data(album.id.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        let safeItemID = itemID.replacingOccurrences(of: "/", with: "_")
        let dir = cacheRoot.appendingPathComponent(String(albumHash), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(safeItemID).jpg")
    }

    private func saveToDisk(image: NSImage, url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return
        }
        try jpeg.write(to: url)
    }
}
