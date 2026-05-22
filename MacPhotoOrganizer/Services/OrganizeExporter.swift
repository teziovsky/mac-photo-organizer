import Foundation
import Photos

@MainActor
final class OrganizeExporter: ObservableObject {
    @Published private(set) var progress: OrganizeProgress?
    @Published private(set) var failures: [OrganizeFailure] = []
    @Published private(set) var isRunning = false
    @Published private(set) var destinationAlbumTitle: String?

    private var exportTask: Task<Void, Never>?
    private var onFinished: (@MainActor () async -> Void)?

    func organize(
        items: [MediaItem],
        sourceAlbum: PhotoAlbum,
        to exportDirectory: URL,
        photosService: PhotosService,
        onFinished: (@MainActor () async -> Void)? = nil
    ) {
        cancel()
        failures = []
        isRunning = true
        self.onFinished = onFinished
        destinationAlbumTitle = PhotosService.destinationAlbumTitle(forSourceAlbumNamed: sourceAlbum.name)
        progress = OrganizeProgress(
            current: 0,
            total: items.count,
            filename: "",
            failedCount: 0,
            skippedCount: 0,
            isComplete: false,
            wasCancelled: false
        )

        let targetTitle = destinationAlbumTitle!
        exportTask = Task {
            await runOrganize(
                items: items,
                sourceAlbum: sourceAlbum,
                targetAlbumTitle: targetTitle,
                exportDirectory: exportDirectory,
                photosService: photosService
            )
        }
    }

    func cancel() {
        exportTask?.cancel()
        exportTask = nil
        if isRunning {
            let current = progress?.current ?? 0
            let total = progress?.total ?? 0
            progress = OrganizeProgress(
                current: current,
                total: total,
                filename: progress?.filename ?? "",
                failedCount: progress?.failedCount ?? 0,
                skippedCount: progress?.skippedCount ?? 0,
                isComplete: true,
                wasCancelled: true
            )
        }
        isRunning = false
    }

    private func runOrganize(
        items: [MediaItem],
        sourceAlbum: PhotoAlbum,
        targetAlbumTitle: String,
        exportDirectory: URL,
        photosService: PhotosService
    ) async {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        var failedCount = 0
        var skippedCount = 0
        var failureList: [OrganizeFailure] = []

        for (index, item) in items.enumerated() {
            if Task.isCancelled { break }

            await MainActor.run {
                progress = OrganizeProgress(
                    current: index,
                    total: items.count,
                    filename: item.filename,
                    failedCount: failedCount,
                    skippedCount: skippedCount,
                    isComplete: false,
                    wasCancelled: false
                )
            }

            guard let asset = item.asset else {
                failedCount += 1
                failureList.append(OrganizeFailure(filename: item.filename, message: "Asset not found"))
                continue
            }

            let destination = uniqueDestinationURL(
                directory: exportDirectory,
                filename: item.filename,
                fileManager: fileManager
            )

            do {
                try await exportAsset(asset, to: destination)
                try await photosService.moveAsset(
                    asset,
                    fromSourceAlbum: sourceAlbum,
                    toAlbumNamed: targetAlbumTitle
                )
            } catch {
                if error is OrganizeSkipError {
                    skippedCount += 1
                    failureList.append(OrganizeFailure(filename: item.filename, message: error.localizedDescription))
                } else {
                    failedCount += 1
                    failureList.append(
                        OrganizeFailure(
                            filename: item.filename,
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }

        let cancelled = Task.isCancelled
        let finished = onFinished
        onFinished = nil

        await MainActor.run {
            failures = failureList
            progress = OrganizeProgress(
                current: items.count,
                total: items.count,
                filename: "",
                failedCount: failedCount,
                skippedCount: skippedCount,
                isComplete: true,
                wasCancelled: cancelled
            )
            isRunning = false
            exportTask = nil
        }

        if !cancelled {
            await finished?()
        }
    }

    private func exportAsset(_ asset: PHAsset, to destination: URL) async throws {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredResource(for: asset, resources: resources) else {
            throw OrganizeExportError.noResource
        }

        if fileManagerExists(destination) {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error {
                    let message = (error as NSError).localizedDescription.lowercased()
                    if message.contains("cloud") || message.contains("not downloaded") {
                        continuation.resume(throwing: OrganizeSkipError.iCloudOnly)
                        return
                    }
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func preferredResource(for asset: PHAsset, resources: [PHAssetResource]) -> PHAssetResource? {
        if asset.mediaType == .video {
            return resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo })
                ?? resources.first
        }
        return resources.first(where: { $0.type == .photo || $0.type == .fullSizeVideo })
            ?? resources.first
    }

    private func uniqueDestinationURL(directory: URL, filename: String, fileManager: FileManager) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    private func fileManagerExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

private enum OrganizeExportError: LocalizedError {
    case noResource

    var errorDescription: String? {
        switch self {
        case .noResource:
            return "No exportable resource found"
        }
    }
}

private enum OrganizeSkipError: LocalizedError {
    case iCloudOnly

    var errorDescription: String? {
        switch self {
        case .iCloudOnly:
            return "Not downloaded from iCloud"
        }
    }
}
