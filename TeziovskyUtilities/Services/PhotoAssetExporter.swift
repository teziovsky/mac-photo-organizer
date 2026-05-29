import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

enum PhotoAssetExporter {
    /// Picks the resource closest to the original file stored in the Photos library (EXIF embedded).
    static func preferredOriginalResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        switch asset.mediaType {
        case .video:
            return resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video })
                ?? resources.first
        case .image:
            return resources.first(where: { $0.type == .fullSizePhoto })
                ?? resources.first(where: { $0.type == .photo })
                ?? resources.first(where: { $0.type == .alternatePhoto })
                ?? resources.first
        default:
            return resources.first
        }
    }

    static func writeOriginalResource(
        for asset: PHAsset,
        to destination: URL,
        skipWriteIfFileExists: Bool = false
    ) async throws {
        guard let resource = preferredOriginalResource(for: asset) else {
            throw PhotoAssetExportError.noResource
        }

        if !skipWriteIfFileExists || !FileManager.default.fileExists(atPath: destination.path) {
            try await writeData(for: resource, to: destination)
        }

        try preserveEmbeddedImageMetadata(from: asset, resource: resource, at: destination)
        try FileDatePreservation.apply(from: asset, to: destination)
    }

    private static func writeData(for resource: PHAssetResource, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error {
                    let message = (error as NSError).localizedDescription.lowercased()
                    if message.contains("cloud") || message.contains("not downloaded") {
                        continuation.resume(throwing: PhotoAssetExportError.iCloudOnly)
                        return
                    }
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Re-embed EXIF/TIFF/GPS when the written bytes are a display proxy; full-size originals are left untouched.
    private static func preserveEmbeddedImageMetadata(
        from asset: PHAsset,
        resource: PHAssetResource,
        at url: URL
    ) throws {
        guard asset.mediaType == .image else { return }
        guard resource.type != .fullSizePhoto else { return }
        guard asset.hasAdjustments || resource.type == .photo else { return }
        guard isImageMetadataType(resource.uniformTypeIdentifier) else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let destinationType = CGImageSourceGetType(source) else {
            return
        }

        let index = 0
        guard var properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return
        }

        properties = mergePhotosMetadata(into: properties, asset: asset)

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".metadata-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)

        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            destinationType,
            1,
            nil
        ) else {
            return
        }

        CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }

        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tempURL, to: url)
    }

    private static func isImageMetadataType(_ uniformTypeIdentifier: String?) -> Bool {
        guard let uniformTypeIdentifier,
              let type = UTType(uniformTypeIdentifier) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private static func mergePhotosMetadata(into properties: [CFString: Any], asset: PHAsset) -> [CFString: Any] {
        var merged = properties

        if let creation = asset.creationDate {
            let exifTimestamp = exifDateString(creation)
            var exif = merged[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
            exif[kCGImagePropertyExifDateTimeOriginal] = exifTimestamp
            exif[kCGImagePropertyExifDateTimeDigitized] = exifTimestamp
            merged[kCGImagePropertyExifDictionary] = exif

            var tiff = merged[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFDateTime] = exifTimestamp
            merged[kCGImagePropertyTIFFDictionary] = tiff
        }

        if let location = asset.location {
            var gps = merged[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
            let latitude = location.coordinate.latitude
            let longitude = location.coordinate.longitude
            gps[kCGImagePropertyGPSLatitude] = abs(latitude)
            gps[kCGImagePropertyGPSLatitudeRef] = latitude >= 0 ? "N" : "S"
            gps[kCGImagePropertyGPSLongitude] = abs(longitude)
            gps[kCGImagePropertyGPSLongitudeRef] = longitude >= 0 ? "E" : "W"
            if location.altitude != 0 {
                gps[kCGImagePropertyGPSAltitude] = abs(location.altitude)
                gps[kCGImagePropertyGPSAltitudeRef] = location.altitude < 0 ? 1 : 0
            }
            merged[kCGImagePropertyGPSDictionary] = gps
        }

        return merged
    }

    private static func exifDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum PhotoAssetExportError: LocalizedError {
    case noResource
    case iCloudOnly

    var errorDescription: String? {
        switch self {
        case .noResource:
            return "No exportable resource found"
        case .iCloudOnly:
            return "Not downloaded from iCloud"
        }
    }
}
