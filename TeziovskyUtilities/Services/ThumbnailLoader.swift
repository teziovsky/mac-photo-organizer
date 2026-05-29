import AppKit
import CryptoKit
import Foundation
import Photos

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let imageManager = PHImageManager.default()
    private var memoryCache: [String: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 400, height: 400)
    private let requestTimeoutSeconds: UInt64 = 12
    private let maxDiskCacheBytes: Int64 = 500 * 1024 * 1024

    private var cacheRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TeziovskyUtilities/Thumbnails", isDirectory: true)
    }

    func cachedImage(for itemID: String) -> NSImage? {
        memoryCache[itemID]
    }

    func thumbnail(for item: MediaItem, album: PhotoAlbum, asset: PHAsset?) async -> NSImage? {
        if let cached = memoryCache[item.id] {
            return cached
        }

        let diskPath = diskCacheURL(album: album, itemID: item.id)
        if FileManager.default.fileExists(atPath: diskPath.path),
           let image = NSImage(contentsOf: diskPath) {
            memoryCache[item.id] = image
            return image
        }

        guard let asset else { return nil }

        let image = await requestImage(for: asset)
        guard let image else { return nil }

        memoryCache[item.id] = image
        try? saveToDisk(image: image, url: diskPath)
        await pruneDiskCacheIfNeeded()
        return image
    }

    func clearMemoryCache() {
        memoryCache.removeAll()
    }

    func clearMemoryCache(forAlbumID albumID: String) async {
        memoryCache.removeAll()
        await pruneAlbumDiskCache(albumID: albumID)
    }

    private func requestImage(for asset: PHAsset) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            var resumed = false
            let resumeOnce: (NSImage?) -> Void = { image in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }

            let requestID = imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    resumeOnce(nil)
                    _ = error
                    return
                }
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    resumeOnce(nil)
                    return
                }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                resumeOnce(image)
            }

            Task {
                try? await Task.sleep(nanoseconds: requestTimeoutSeconds * 1_000_000_000)
                if !resumed {
                    imageManager.cancelImageRequest(requestID)
                    resumeOnce(nil)
                }
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

    private func pruneAlbumDiskCache(albumID: String) async {
        let albumHash = SHA256.hash(data: Data(albumID.utf8)).compactMap { String(format: "%02x", $0) }.joined().prefix(16)
        let dir = cacheRoot.appendingPathComponent(String(albumHash), isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    private func pruneDiskCacheIfNeeded() async {
        let root = cacheRoot
        let cacheLimit = maxDiskCacheBytes
        let files: [(url: URL, size: Int64, date: Date)] = await Task.detached {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var collected: [(url: URL, size: Int64, date: Date)] = []
            var total: Int64 = 0
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "jpg" else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size = Int64(values?.fileSize ?? 0)
                let date = values?.contentModificationDate ?? .distantPast
                collected.append((url, size, date))
                total += size
            }
            guard total > cacheLimit else { return [] }
            return collected
        }.value

        guard !files.isEmpty else { return }

        var sorted = files
        sorted.sort { $0.date < $1.date }
        var removed: Int64 = 0
        let target = files.reduce(0) { $0 + $1.size } - cacheLimit / 2
        for file in sorted {
            guard removed < target else { break }
            try? FileManager.default.removeItem(at: file.url)
            removed += file.size
        }
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
