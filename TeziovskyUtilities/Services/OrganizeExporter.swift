import Foundation
import Photos

@MainActor
final class OrganizeExporter: ObservableObject {
    /// Albums at or above this size keep the Mac awake for the full export.
    static let largeAlbumSleepThreshold = 50

    @Published private(set) var progress: OrganizeProgress?
    @Published private(set) var failures: [OrganizeFailure] = []
    @Published private(set) var isRunning = false
    @Published private(set) var destinationAlbumTitle: String?

    private var exportTask: Task<Void, Never>?
    private var onFinished: (@MainActor () async -> Void)?
    private let directoryAccess = ExportDirectoryAccess()
    private let sleepAssertion = SleepAssertion()

    func organize(
        items: [MediaItem],
        assetsByID: [String: PHAsset],
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
            movedCount: 0,
            isComplete: false,
            wasCancelled: false
        )

        if items.count >= Self.largeAlbumSleepThreshold {
            sleepAssertion.acquire(
                reason: "Exporting \(items.count) items from “\(sourceAlbum.name)”"
            )
        }

        let targetTitle = destinationAlbumTitle!
        photosService.beginDeferringAlbumReloadFromLibraryChanges()
        exportTask = Task {
            await runOrganize(
                items: items,
                assetsByID: assetsByID,
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
                movedCount: progress?.movedCount ?? 0,
                isComplete: true,
                wasCancelled: true
            )
        }
        isRunning = false
        directoryAccess.endAccess()
        sleepAssertion.release()
    }

    private func runOrganize(
        items: [MediaItem],
        assetsByID: [String: PHAsset],
        sourceAlbum: PhotoAlbum,
        targetAlbumTitle: String,
        exportDirectory: URL,
        photosService: PhotosService
    ) async {
        guard let scopedDirectory = directoryAccess.beginAccess() else {
            await finishWithAccessError(items: items)
            await photosService.endDeferringAlbumReloadFromLibraryChanges()
            return
        }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: scopedDirectory, withIntermediateDirectories: true)

        var failedCount = 0
        var skippedCount = 0
        var movedCount = 0
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
                    movedCount: movedCount,
                    isComplete: false,
                    wasCancelled: false
                )
            }

            guard let asset = assetsByID[item.id] else {
                failedCount += 1
                failureList.append(OrganizeFailure(filename: item.filename, message: "Asset not found"))
                continue
            }

            let safeName = SafeFilename.sanitize(item.filename, fallback: item.id)
            let itemCreationDate = asset.creationDate ?? asset.modificationDate ?? Date()
            let itemDirectory = OrganizeExportDirectory.exportDirectory(
                base: scopedDirectory,
                selectedDirectoryName: exportDirectory.lastPathComponent,
                creationDate: itemCreationDate,
                organizeByYearEnabled: AppSettings.organizeByYearEnabled
            )
            try? fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            let destination = uniqueDestinationURL(
                directory: itemDirectory,
                filename: safeName,
                fileManager: fileManager
            )

            guard let destination else {
                failedCount += 1
                failureList.append(OrganizeFailure(filename: item.filename, message: "Invalid export path"))
                continue
            }

            do {
                try await exportAsset(asset, to: destination)
                try await photosService.moveAsset(
                    asset,
                    fromSourceAlbum: sourceAlbum,
                    toAlbumNamed: targetAlbumTitle
                )
                movedCount += 1
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
                movedCount: movedCount,
                isComplete: true,
                wasCancelled: cancelled
            )
            isRunning = false
            exportTask = nil
        }

        directoryAccess.endAccess()
        sleepAssertion.release()

        await photosService.endDeferringAlbumReloadFromLibraryChanges()
        if !cancelled {
            await finished?()
        }
    }

    private func finishWithAccessError(items: [MediaItem]) async {
        failures = [
            OrganizeFailure(
                filename: "",
                message: "Could not access the export folder. Choose it again when organizing."
            )
        ]
        progress = OrganizeProgress(
            current: 0,
            total: items.count,
            filename: "",
            failedCount: items.count,
            skippedCount: 0,
            movedCount: 0,
            isComplete: true,
            wasCancelled: false
        )
        isRunning = false
        exportTask = nil
        onFinished = nil
        sleepAssertion.release()
    }

    private func exportAsset(_ asset: PHAsset, to destination: URL) async throws {
        do {
            try await PhotoAssetExporter.writeOriginalResource(
                for: asset,
                to: destination,
                skipWriteIfFileExists: true
            )
        } catch let error as PhotoAssetExportError {
            switch error {
            case .noResource:
                throw OrganizeExportError.noResource
            case .iCloudOnly:
                throw OrganizeSkipError.iCloudOnly
            }
        }
    }

    private func uniqueDestinationURL(
        directory: URL,
        filename: String,
        fileManager: FileManager
    ) -> URL? {
        guard var candidate = SafeFilename.fileURL(in: directory, filename: filename, fallback: "photo") else {
            return nil
        }

        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            guard let next = SafeFilename.fileURL(in: directory, filename: newName, fallback: "photo") else {
                return nil
            }
            candidate = next
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
