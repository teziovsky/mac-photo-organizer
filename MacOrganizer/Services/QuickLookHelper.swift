import AppKit
import Photos
import Quartz
import QuickLookUI

@MainActor
enum QuickLookHelper {
    private static var tempExports: [String: URL] = [:]
    private static var activeDataSource: PreviewDataSource?

    static func preview(item: MediaItem) async {
        guard let asset = item.asset else { return }

        do {
            let url = try await exportURL(for: asset, filename: item.filename)
            let dataSource = PreviewDataSource(url: url)
            activeDataSource = dataSource
            let panel = QLPreviewPanel.shared()
            panel?.dataSource = dataSource
            panel?.reloadData()
            panel?.makeKeyAndOrderFront(nil)
        } catch {
            NSSound.beep()
        }
    }

    static func closePreview() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    private static func exportURL(for asset: PHAsset, filename: String) async throws -> URL {
        if let cached = tempExports[asset.localIdentifier],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacOrganizer-QuickLook", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeName = filename.isEmpty ? "preview.dat" : filename
        let destination = tempDir.appendingPathComponent(
            "\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_"))-\(safeName)"
        )

        if FileManager.default.fileExists(atPath: destination.path) {
            tempExports[asset.localIdentifier] = destination
            return destination
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video || $0.type == .fullSizeVideo })
            ?? resources.first else {
            throw QuickLookError.noResource
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        tempExports[asset.localIdentifier] = destination
        return destination
    }
}

private enum QuickLookError: LocalizedError {
    case noResource

    var errorDescription: String? {
        "Could not load preview"
    }
}

private final class PreviewDataSource: NSObject, QLPreviewPanelDataSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as QLPreviewItem
    }
}
