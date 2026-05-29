import AVFoundation
import Foundation

enum VideoMetadataTransferError: LocalizedError {
    case exportSessionUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportSessionUnavailable:
            return "Could not create an export session to copy video metadata."
        case .exportFailed(let message):
            return message
        }
    }
}

/// Best-effort native copy of container-level metadata (creation date, location, and other
/// common metadata) from a source video onto a compressed video using an AVFoundation
/// passthrough export (no re-encode, so quality is preserved).
enum VideoMetadataTransfer {
    static func transfer(from sourceURL: URL, to compressedURL: URL) async throws {
        let sourceAsset = AVURLAsset(url: sourceURL)
        let metadata = try await sourceAsset.load(.commonMetadata)
        guard !metadata.isEmpty else { return }

        let compressedAsset = AVURLAsset(url: compressedURL)
        guard let session = AVAssetExportSession(
            asset: compressedAsset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw VideoMetadataTransferError.exportSessionUnavailable
        }

        let outputType = outputFileType(for: compressedURL, session: session)
        let tempURL = compressedURL
            .deletingLastPathComponent()
            .appendingPathComponent(".dronemeta-\(UUID().uuidString)")
            .appendingPathExtension(compressedURL.pathExtension.isEmpty ? "mov" : compressedURL.pathExtension)

        session.outputURL = tempURL
        session.outputFileType = outputType
        session.metadata = metadata
        session.shouldOptimizeForNetworkUse = true

        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await runExport(session)

        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw VideoMetadataTransferError.exportFailed("Export produced no output file.")
        }

        try FileManager.default.removeItem(at: compressedURL)
        try FileManager.default.moveItem(at: tempURL, to: compressedURL)
    }

    private static func outputFileType(for url: URL, session: AVAssetExportSession) -> AVFileType {
        let supported = session.supportedFileTypes
        let preferred: AVFileType
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v":
            preferred = .mp4
        case "mov", "qt":
            preferred = .mov
        case "m4a":
            preferred = .m4a
        default:
            preferred = .mov
        }
        if supported.contains(preferred) { return preferred }
        return supported.first ?? preferred
    }

    private static func runExport(_ session: AVAssetExportSession) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw VideoMetadataTransferError.exportFailed("Metadata export was cancelled.")
        default:
            let message = session.error?.localizedDescription ?? "Unknown export error."
            throw VideoMetadataTransferError.exportFailed(message)
        }
    }
}
