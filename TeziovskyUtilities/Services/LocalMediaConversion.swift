import AVFoundation
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LocalMediaConversionPlanner {
    private static let heicExtensions: Set<String> = ["heic", "heif"]
    private static let legacyVideoExtensions: Set<String> = [
        "3gp", "avi", "flv", "m2ts", "m4v", "mkv", "mpeg", "mpg", "mts", "qt", "vob", "wmv"
    ]

    static func isVideoCandidate(_ url: URL) -> Bool {
        MediaFileClassifier.isVideo(url.lastPathComponent)
            || legacyVideoExtensions.contains(url.pathExtension.lowercased())
    }

    static func makeCandidate(
        fileURL: URL,
        relativePath: String,
        rootDirectory: URL,
        config: LocalMediaConversionConfig
    ) async -> LocalMediaConversionItem? {
        if config.keepOriginals, LocalMediaConverter.hasConversionMarker(fileURL) {
            return nil
        }
        let fileExtension = fileURL.pathExtension.lowercased()
        let kind: LocalMediaConversionKind

        if config.convertHEIC, heicExtensions.contains(fileExtension) {
            kind = .heicToJPEG
        } else if config.convertLegacyVideos,
                  isVideoCandidate(fileURL),
                  await videoNeedsConversion(fileURL, fileExtension: fileExtension) {
            kind = .legacyVideo(config.videoOutputContainer, config.videoCodec)
        } else {
            return nil
        }

        let outputExtension: String
        switch kind {
        case .heicToJPEG:
            outputExtension = "jpg"
        case .legacyVideo(let container, _):
            outputExtension = container.fileExtension
        }
        let base = fileURL.deletingPathExtension().lastPathComponent
        let preferredName = fileExtension == outputExtension
            ? "\(base)-converted.\(outputExtension)"
            : "\(base).\(outputExtension)"
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(preferredName)

        return LocalMediaConversionItem(
            sourceURL: fileURL,
            sourceRelativePath: relativePath,
            destinationURL: destination,
            destinationRelativePath: makeRelativePath(for: destination, root: rootDirectory),
            kind: kind,
            keepOriginal: config.keepOriginals,
            destinationWasRenamed: false
        )
    }

    static func resolveCollisions(
        _ candidates: [LocalMediaConversionItem],
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) -> [LocalMediaConversionItem] {
        var reservedPaths = Set<String>()
        return candidates
            .sorted {
                $0.sourceRelativePath.localizedStandardCompare($1.sourceRelativePath) == .orderedAscending
            }
            .map { item in
                let destination = uniqueDestination(
                    preferred: item.destinationURL,
                    reservedPaths: &reservedPaths,
                    fileManager: fileManager
                )
                return LocalMediaConversionItem(
                    sourceURL: item.sourceURL,
                    sourceRelativePath: item.sourceRelativePath,
                    destinationURL: destination,
                    destinationRelativePath: makeRelativePath(for: destination, root: rootDirectory),
                    kind: item.kind,
                    keepOriginal: item.keepOriginal,
                    destinationWasRenamed: destination.lastPathComponent != item.destinationURL.lastPathComponent
                )
            }
    }

    private static func videoNeedsConversion(_ url: URL, fileExtension: String) async -> Bool {
        guard !legacyVideoExtensions.contains(fileExtension),
              fileExtension == "mp4" || fileExtension == "mov" else {
            return true
        }

        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first else {
            return true
        }
        let codec = CMFormatDescriptionGetMediaSubType(description)
        return !modernVideoCodecs.contains(codec)
    }

    private static let modernVideoCodecs: Set<FourCharCode> = [
        kCMVideoCodecType_H264,
        kCMVideoCodecType_HEVC,
        kCMVideoCodecType_AppleProRes422,
        kCMVideoCodecType_AppleProRes422HQ,
        kCMVideoCodecType_AppleProRes422LT,
        kCMVideoCodecType_AppleProRes422Proxy,
        kCMVideoCodecType_AppleProRes4444
    ]

    private static func uniqueDestination(
        preferred: URL,
        reservedPaths: inout Set<String>,
        fileManager: FileManager
    ) -> URL {
        var candidate = preferred
        let base = preferred.deletingPathExtension().lastPathComponent
        let fileExtension = preferred.pathExtension
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path)
            || reservedPaths.contains(candidate.standardizedFileURL.path) {
            candidate = preferred.deletingLastPathComponent()
                .appendingPathComponent("\(base) (\(counter)).\(fileExtension)")
            counter += 1
        }
        reservedPaths.insert(candidate.standardizedFileURL.path)
        return candidate
    }

    private static func makeRelativePath(for url: URL, root: URL) -> String {
        let rootPath = normalizeSystemAlias(root.standardizedFileURL.path)
        let path = normalizeSystemAlias(url.standardizedFileURL.path)
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func normalizeSystemAlias(_ path: String) -> String {
        for alias in ["/var", "/tmp", "/etc"] where path.hasPrefix("/private\(alias)/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}

enum LocalMediaConversionError: LocalizedError {
    case unreadableImage
    case imageWriteFailed
    case exportUnavailable
    case unsupportedOutput
    case exportFailed(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return "The HEIC image could not be decoded."
        case .imageWriteFailed: return "The JPEG image could not be written."
        case .exportUnavailable: return "This video cannot be converted by AVFoundation."
        case .unsupportedOutput: return "The selected video output is unsupported for this file."
        case .exportFailed(let message): return message
        case .verificationFailed: return "The converted file could not be verified."
        }
    }
}

private final class MediaConversionCancellation: @unchecked Sendable {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }

    func cancel() {
        session.cancelExport()
    }
}

enum LocalMediaConverter {
    static func convert(
        _ item: LocalMediaConversionItem,
        fileManager: FileManager = .default
    ) async throws {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: item.sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !fileManager.fileExists(atPath: item.destinationURL.path) else {
            throw CocoaError(
                .fileWriteFileExists,
                userInfo: [NSLocalizedDescriptionKey: "The previewed destination now exists. Rescan first."]
            )
        }

        let dates = try item.sourceURL.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        )
        do {
            switch item.kind {
            case .heicToJPEG:
                try convertHEIC(item.sourceURL, to: item.destinationURL)
            case .legacyVideo(let container, let codec):
                try await convertVideo(
                    item.sourceURL,
                    to: item.destinationURL,
                    container: container,
                    codec: codec
                )
            }
            try await verify(item.destinationURL, kind: item.kind)
            let created = dates.creationDate ?? dates.contentModificationDate ?? Date()
            let modified = dates.contentModificationDate ?? created
            try FileDatePreservation.applyFileDates(
                to: item.destinationURL,
                created: created,
                modified: modified
            )
            try Task.checkCancellation()
            if item.keepOriginal {
                markConverted(item.sourceURL, destination: item.destinationURL)
            } else {
                try fileManager.removeItem(at: item.sourceURL)
            }
        } catch {
            try? fileManager.removeItem(at: item.destinationURL)
            throw error
        }
    }

    private static let conversionMarker = "com.teziovsky.utilities.converted-media"

    static func hasConversionMarker(_ url: URL) -> Bool {
        url.path.withCString { path in
            conversionMarker.withCString { name in
                getxattr(path, name, nil, 0, 0, 0) > 0
            }
        }
    }

    private static func markConverted(_ sourceURL: URL, destination: URL) {
        let value = Array(destination.lastPathComponent.utf8)
        sourceURL.path.withCString { path in
            conversionMarker.withCString { name in
                value.withUnsafeBytes { bytes in
                    _ = setxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
    }

    private static func convertHEIC(_ sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let destination = CGImageDestinationCreateWithURL(
                  destinationURL as CFURL,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              ) else {
            throw LocalMediaConversionError.unreadableImage
        }
        var properties = (
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        ) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = 1.0
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LocalMediaConversionError.imageWriteFailed
        }
    }

    private static func convertVideo(
        _ sourceURL: URL,
        to destinationURL: URL,
        container: LocalVideoOutputContainer,
        codec: LocalVideoCodec
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let preset = codec == .h264
            ? AVAssetExportPresetHighestQuality
            : AVAssetExportPresetHEVCHighestQuality
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            throw LocalMediaConversionError.exportUnavailable
        }
        let outputType: AVFileType = container == .mp4 ? .mp4 : .mov
        guard session.supportedFileTypes.contains(outputType) else {
            throw LocalMediaConversionError.unsupportedOutput
        }
        session.outputURL = destinationURL
        session.outputFileType = outputType
        session.shouldOptimizeForNetworkUse = container == .mp4
        session.metadata = (try? await asset.load(.commonMetadata)) ?? []
        try await runExport(session)
    }

    private static func runExport(_ session: AVAssetExportSession) async throws {
        try Task.checkCancellation()
        let cancellation = MediaConversionCancellation(session: session)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
        } onCancel: {
            cancellation.cancel()
        }

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw CancellationError()
        default:
            throw LocalMediaConversionError.exportFailed(
                session.error?.localizedDescription ?? "Unknown video conversion error."
            )
        }
    }

    private static func verify(_ url: URL, kind: LocalMediaConversionKind) async throws {
        switch kind {
        case .heicToJPEG:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0 else {
                throw LocalMediaConversionError.verificationFailed
            }
        case .legacyVideo(_, let expectedCodec):
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable),
                  try await hasExpectedCodecs(asset, videoCodec: expectedCodec) else {
                throw LocalMediaConversionError.verificationFailed
            }
        }
    }

    private static func hasExpectedCodecs(_ asset: AVAsset, videoCodec: LocalVideoCodec) async throws -> Bool {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return false
        }
        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        let expectedVideoCodec = videoCodec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        guard videoDescriptions.contains(where: {
            CMFormatDescriptionGetMediaSubType($0) == expectedVideoCodec
        }) else {
            return false
        }

        for audioTrack in try await asset.loadTracks(withMediaType: .audio) {
            let descriptions = try await audioTrack.load(.formatDescriptions)
            guard descriptions.allSatisfy({
                CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC
            }) else {
                return false
            }
        }
        return true
    }
}
