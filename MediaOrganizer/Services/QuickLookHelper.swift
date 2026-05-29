import AppKit
import Photos
import Quartz
import QuickLookUI

@MainActor
enum QuickLookHelper {
    private static var tempExports: [String: URL] = [:]
    private static var activeDataSource: PreviewDataSource?

    static func preview(item: MediaItem, asset: PHAsset?) async throws {
        guard let asset else {
            throw QuickLookError.noAsset
        }

        let url = try await exportURL(for: asset, filename: item.filename)
        let dataSource = PreviewDataSource(url: url)
        activeDataSource = dataSource
        let panel = QLPreviewPanel.shared()
        panel?.dataSource = dataSource
        panel?.reloadData()
        panel?.makeKeyAndOrderFront(nil)
    }

    static var isPanelVisible: Bool {
        QLPreviewPanel.shared()?.isVisible ?? false
    }

    static func closePreview() {
        QLPreviewPanel.shared()?.orderOut(nil)
        activeDataSource = nil
        pruneTempExports(keeping: [])
    }

    private static func exportURL(for asset: PHAsset, filename: String) async throws -> URL {
        if let cached = tempExports[asset.localIdentifier],
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaOrganizer-QuickLook", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        pruneTempExports(keeping: Array(tempExports.keys))

        let safeName = SafeFilename.sanitize(filename, fallback: "preview.dat")
        let destination = tempDir.appendingPathComponent(
            "\(asset.localIdentifier.replacingOccurrences(of: "/", with: "_"))-\(safeName)"
        )

        guard SafeFilename.isContained(destination, in: tempDir) else {
            throw QuickLookError.invalidPath
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            tempExports[asset.localIdentifier] = destination
            return destination
        }

        do {
            try await PhotoAssetExporter.writeOriginalResource(for: asset, to: destination)
        } catch PhotoAssetExportError.noResource {
            throw QuickLookError.noResource
        }

        tempExports[asset.localIdentifier] = destination
        return destination
    }

    private static func pruneTempExports(keeping activeIDs: [String]) {
        let keep = Set(activeIDs)
        for (id, url) in tempExports where !keep.contains(id) {
            try? FileManager.default.removeItem(at: url)
            tempExports.removeValue(forKey: id)
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaOrganizer-QuickLook", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else {
            return
        }
        let keepPaths = Set(tempExports.values.map(\.path))
        for url in contents where !keepPaths.contains(url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private enum QuickLookError: LocalizedError {
    case noResource
    case noAsset
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .noResource:
            return "Could not load preview"
        case .noAsset:
            return "Photo is no longer available in the library"
        case .invalidPath:
            return "Could not create a safe preview file path"
        }
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
