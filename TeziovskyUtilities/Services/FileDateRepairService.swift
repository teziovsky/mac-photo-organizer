import Foundation

struct FileDateScanOutput: Sendable {
    let relativePath: String
    let conversionCandidate: LocalMediaConversionItem?
    let repairItem: FileDateRepairItem?
    let organizationCandidate: LocalMediaOrganizationItem?
    let failure: FileDateRepairFailure?
}

struct FileDateScanResult: Sendable {
    let conversionItems: [LocalMediaConversionItem]
    let items: [FileDateRepairItem]
    let organizationItems: [LocalMediaOrganizationItem]
    let organizationSkippedCount: Int
    let failures: [FileDateRepairFailure]
    let scannedFileCount: Int
}

enum FileDateRepairScanner {
    static let maximumConcurrentReads = 8

    static func scan(
        directory: URL,
        supportedExtensions: Set<String>,
        conversionConfig: LocalMediaConversionConfig = .default,
        progress: @escaping @Sendable (FileDateRepairProgress) async -> Void
    ) async throws -> FileDateScanResult {
        let enumeration = try enumerateFiles(in: directory, supportedExtensions: supportedExtensions)
        var failures = enumeration.failures
        var conversionCandidates: [LocalMediaConversionItem] = []
        var items: [FileDateRepairItem] = []
        var organizationCandidates: [LocalMediaOrganizationItem] = []
        var organizationSkippedCount = 0
        var nextIndex = 0
        var processed = 0

        try await withThrowingTaskGroup(of: FileDateScanOutput.self) { group in
            func addNext() {
                guard nextIndex < enumeration.files.count else { return }
                let file = enumeration.files[nextIndex]
                nextIndex += 1
                group.addTask {
                    try Task.checkCancellation()
                    let conversionCandidate = await LocalMediaConversionPlanner.makeCandidate(
                        fileURL: file.url,
                        relativePath: file.relativePath,
                        rootDirectory: directory,
                        config: conversionConfig
                    )
                    do {
                        let isVideo = LocalMediaConversionPlanner.isVideoCandidate(file.url)
                        let evidence = try await MediaMetadataReader.readDateEvidence(
                            url: file.url,
                            isVideo: isVideo
                        )
                        let repairItem = FileDateRepairPlanner.makeItem(
                            fileURL: file.url,
                            relativePath: file.relativePath,
                            evidence: evidence
                        )
                        let organizationCandidate = LocalMediaOrganizationPlanner.makeCandidate(
                            fileURL: file.url,
                            relativePath: file.relativePath,
                            rootDirectory: directory,
                            evidence: evidence,
                            isVideo: isVideo
                        )
                        return FileDateScanOutput(
                            relativePath: file.relativePath,
                            conversionCandidate: conversionCandidate,
                            repairItem: repairItem,
                            organizationCandidate: organizationCandidate,
                            failure: nil
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return FileDateScanOutput(
                            relativePath: file.relativePath,
                            conversionCandidate: conversionCandidate,
                            repairItem: nil,
                            organizationCandidate: nil,
                            failure: FileDateRepairFailure(
                                relativePath: file.relativePath,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            }

            for _ in 0..<min(maximumConcurrentReads, enumeration.files.count) {
                addNext()
            }

            while let output = try await group.next() {
                try Task.checkCancellation()
                processed += 1
                if let item = output.conversionCandidate { conversionCandidates.append(item) }
                if let item = output.repairItem { items.append(item) }
                if let item = output.organizationCandidate { organizationCandidates.append(item) }
                if output.organizationCandidate == nil, output.failure == nil {
                    organizationSkippedCount += 1
                }
                if let failure = output.failure { failures.append(failure) }
                if processed == enumeration.files.count || processed.isMultiple(of: 20) {
                    await progress(
                        FileDateRepairProgress(
                            processed: processed,
                            total: enumeration.files.count,
                            currentPath: output.relativePath
                        )
                    )
                }
                addNext()
            }
        }

        return FileDateScanResult(
            conversionItems: LocalMediaConversionPlanner.resolveCollisions(
                conversionCandidates,
                rootDirectory: directory
            ),
            items: items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending },
            organizationItems: LocalMediaOrganizationPlanner.resolveCollisions(
                organizationCandidates,
                rootDirectory: directory
            ),
            organizationSkippedCount: organizationSkippedCount,
            failures: failures,
            scannedFileCount: enumeration.files.count
        )
    }

    private static func enumerateFiles(
        in directory: URL,
        supportedExtensions: Set<String>,
        fileManager: FileManager = .default
    ) throws -> (
        files: [(url: URL, relativePath: String)],
        failures: [FileDateRepairFailure]
    ) {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey
        ]
        var failures: [FileDateRepairFailure] = []
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                failures.append(
                    FileDateRepairFailure(
                        relativePath: relativePath(for: url, root: directory),
                        message: error.localizedDescription
                    )
                )
                return true
            }
        ) else {
            return ([], [
                FileDateRepairFailure(
                    relativePath: directory.lastPathComponent,
                    message: "The directory could not be enumerated."
                )
            ])
        }

        var files: [(URL, String)] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true || values.isPackage == true {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                guard values.isRegularFile == true,
                      FileDateRepairExtensions.supports(url, extensions: supportedExtensions) else {
                    continue
                }
                files.append((url, relativePath(for: url, root: directory)))
            } catch {
                failures.append(
                    FileDateRepairFailure(
                        relativePath: relativePath(for: url, root: directory),
                        message: error.localizedDescription
                    )
                )
            }
        }
        return (files, failures)
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

enum LocalMediaOrganizer {
    static func move(_ item: LocalMediaOrganizationItem, fileManager: FileManager = .default) async throws {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: item.sourceURL.path) else {
            throw CocoaError(
                .fileNoSuchFile,
                userInfo: [NSLocalizedDescriptionKey: "The source file no longer exists. Rescan before organizing."]
            )
        }
        guard !fileManager.fileExists(atPath: item.destinationURL.path) else {
            throw CocoaError(
                .fileWriteFileExists,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The previewed destination now exists. Rescan to generate a new collision-safe name."
                ]
            )
        }

        let evidence = try await MediaMetadataReader.readDateEvidence(
            url: item.sourceURL,
            isVideo: item.isVideo
        )
        guard let oldest = FileDateRepairPlanner.oldestPlausibleEvidence(in: evidence),
              abs(oldest.date.timeIntervalSince(item.proposedDate)) <=
              FileDateRepairPlanner.timestampTolerance else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSLocalizedDescriptionKey: "Dates changed since the preview. Rescan before organizing."]
            )
        }

        try Task.checkCancellation()
        try fileManager.createDirectory(
            at: item.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: item.sourceURL, to: item.destinationURL)
    }
}

@MainActor
final class LocalPhotosService: ObservableObject {
    @Published private(set) var directory: URL?
    @Published private(set) var conversionItems: [LocalMediaConversionItem] = []
    @Published private(set) var items: [FileDateRepairItem] = []
    @Published private(set) var organizationItems: [LocalMediaOrganizationItem] = []
    @Published private(set) var organizationSkippedCount = 0
    @Published private(set) var failures: [FileDateRepairFailure] = []
    @Published private(set) var progress = FileDateRepairProgress()
    @Published private(set) var conversionProgress = FileDateRepairProgress()
    @Published private(set) var organizationProgress = FileDateRepairProgress()
    @Published private(set) var conversionSummary: LocalMediaConversionSummary?
    @Published private(set) var organizationSummary: LocalMediaOrganizationSummary?
    @Published private(set) var isScanning = false
    @Published private(set) var isConverting = false
    @Published private(set) var isRepairing = false
    @Published private(set) var isOrganizing = false
    @Published private(set) var repairedIDs: Set<String> = []
    @Published private(set) var attemptedIDs: Set<String> = []
    @Published private(set) var scannedFileCount = 0
    @Published private(set) var cancellationMessage: String?
    @Published var chunkSize = 100

    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    var isRunning: Bool { isScanning || isConverting || isRepairing || isOrganizing }

    var pendingItems: [FileDateRepairItem] {
        items.filter { !attemptedIDs.contains($0.id) }
    }

    var currentChunk: [FileDateRepairItem] {
        FileDateRepairChunker.next(from: items, attemptedIDs: attemptedIDs, size: chunkSize)
    }

    func scan(directory: URL) {
        cancel()
        resetResults()
        self.directory = directory
        isScanning = true
        cancellationMessage = nil
        let extensions = FileDateRepairExtensions.parse(AppSettings.localMediaExtensions)
        let conversionConfig = AppSettings.localMediaConversionConfig
        let operationID = UUID()
        self.operationID = operationID

        operationTask = Task { [weak self] in
            guard let self else { return }
            let didAccess = directory.startAccessingSecurityScopedResource()
            defer {
                if didAccess { directory.stopAccessingSecurityScopedResource() }
                if self.operationID == operationID {
                    isScanning = false
                    operationTask = nil
                    self.operationID = nil
                }
            }

            do {
                let result = try await FileDateRepairScanner.scan(
                    directory: directory,
                    supportedExtensions: extensions,
                    conversionConfig: conversionConfig
                ) { progress in
                    await MainActor.run {
                        if self.operationID == operationID {
                            self.progress = progress
                        }
                    }
                }
                try Task.checkCancellation()
                guard self.operationID == operationID else { return }
                conversionItems = result.conversionItems
                items = result.items
                organizationItems = result.organizationItems
                organizationSkippedCount = result.organizationSkippedCount
                failures = result.failures
                scannedFileCount = result.scannedFileCount
            } catch is CancellationError {
                return
            } catch {
                guard self.operationID == operationID else { return }
                failures.append(
                    FileDateRepairFailure(
                        relativePath: directory.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    func repairCurrentChunk() {
        repair(items: currentChunk)
    }

    func repairAll() {
        repair(items: pendingItems)
    }

    private func repair(items chunk: [FileDateRepairItem]) {
        guard !isRunning, !chunk.isEmpty, let directory else { return }
        isRepairing = true
        cancellationMessage = nil
        progress = FileDateRepairProgress(total: chunk.count)
        let operationID = UUID()
        self.operationID = operationID

        operationTask = Task { [weak self] in
            guard let self else { return }
            let didAccess = directory.startAccessingSecurityScopedResource()
            defer {
                if didAccess { directory.stopAccessingSecurityScopedResource() }
                if self.operationID == operationID {
                    isRepairing = false
                    operationTask = nil
                    self.operationID = nil
                }
            }

            for (index, item) in chunk.enumerated() {
                guard !Task.isCancelled, self.operationID == operationID else { return }
                progress = FileDateRepairProgress(
                    processed: index,
                    total: chunk.count,
                    currentPath: item.relativePath
                )
                do {
                    try await repair(item)
                    guard self.operationID == operationID else { return }
                    repairedIDs.insert(item.id)
                } catch is CancellationError {
                    return
                } catch {
                    guard self.operationID == operationID else { return }
                    failures.append(
                        FileDateRepairFailure(relativePath: item.relativePath, message: error.localizedDescription)
                    )
                }
                attemptedIDs.insert(item.id)
                progress.processed = index + 1
            }
        }
    }

    func organizeAll() {
        guard !isRunning, !organizationItems.isEmpty, let directory else { return }
        let plannedItems = organizationItems
        let skippedCount = organizationSkippedCount
        isOrganizing = true
        cancellationMessage = nil
        organizationSummary = LocalMediaOrganizationSummary(
            skipped: skippedCount,
            total: plannedItems.count
        )
        organizationProgress = FileDateRepairProgress(total: plannedItems.count)
        let operationID = UUID()
        self.operationID = operationID

        operationTask = Task { [weak self] in
            guard let self else { return }
            let didAccess = directory.startAccessingSecurityScopedResource()
            defer {
                if didAccess { directory.stopAccessingSecurityScopedResource() }
                if self.operationID == operationID {
                    isOrganizing = false
                    operationTask = nil
                    self.operationID = nil
                }
            }

            var summary = LocalMediaOrganizationSummary(
                skipped: skippedCount,
                total: plannedItems.count
            )
            var moveFailures: [FileDateRepairFailure] = []
            for (index, item) in plannedItems.enumerated() {
                guard !Task.isCancelled, self.operationID == operationID else {
                    summary.wasCancelled = true
                    organizationSummary = summary
                    return
                }
                organizationProgress = FileDateRepairProgress(
                    processed: index,
                    total: plannedItems.count,
                    currentPath: item.sourceRelativePath
                )
                do {
                    try await organize(item)
                    summary.moved += 1
                } catch is CancellationError {
                    summary.wasCancelled = true
                    organizationSummary = summary
                    return
                } catch {
                    summary.failed += 1
                    moveFailures.append(
                        FileDateRepairFailure(
                            relativePath: item.sourceRelativePath,
                            message: error.localizedDescription
                        )
                    )
                }
                organizationProgress.processed = index + 1
                organizationSummary = summary
            }

            guard !Task.isCancelled, self.operationID == operationID else {
                summary.wasCancelled = true
                organizationSummary = summary
                return
            }
            organizationProgress.currentPath = "Refreshing preview…"
            do {
                let extensions = FileDateRepairExtensions.parse(AppSettings.localMediaExtensions)
                let refreshed = try await FileDateRepairScanner.scan(
                    directory: directory,
                    supportedExtensions: extensions,
                    conversionConfig: AppSettings.localMediaConversionConfig,
                    progress: { _ in }
                )
                guard self.operationID == operationID else { return }
                conversionItems = refreshed.conversionItems
                items = refreshed.items
                organizationItems = refreshed.organizationItems
                organizationSkippedCount = refreshed.organizationSkippedCount
                failures = moveFailures + refreshed.failures
                scannedFileCount = refreshed.scannedFileCount
            } catch is CancellationError {
                summary.wasCancelled = true
            } catch {
                moveFailures.append(
                    FileDateRepairFailure(
                        relativePath: directory.lastPathComponent,
                        message: "Files were organized, but the refresh failed: \(error.localizedDescription)"
                    )
                )
                failures = moveFailures
            }
            organizationSummary = summary
        }
    }

    func cancel() {
        guard isRunning else { return }
        if isScanning {
            cancellationMessage = "Scan cancelled. Rescan the folder to refresh the previews."
        } else if isConverting {
            cancellationMessage = "Conversion cancelled. Completed conversions were kept."
        } else if isRepairing {
            cancellationMessage = "Repair cancelled. Files completed before cancellation remain repaired."
        } else {
            cancellationMessage = "Organization cancelled. Files moved before cancellation remain organized."
        }
        operationTask?.cancel()
    }

    func clearProcessed() {
        guard !isRunning, !repairedIDs.isEmpty else { return }
        items.removeAll { repairedIDs.contains($0.id) }
        repairedIDs = []
        attemptedIDs = attemptedIDs.intersection(Set(items.map(\.id)))
    }

    func failureMessage(for itemID: String) -> String? {
        failures.last(where: { $0.relativePath == itemID })?.message
    }

    func reset() {
        cancel()
        directory = nil
        resetResults()
        cancellationMessage = nil
    }

    private func resetResults() {
        conversionItems = []
        items = []
        organizationItems = []
        organizationSkippedCount = 0
        failures = []
        progress = FileDateRepairProgress()
        conversionProgress = FileDateRepairProgress()
        organizationProgress = FileDateRepairProgress()
        conversionSummary = nil
        organizationSummary = nil
        repairedIDs = []
        attemptedIDs = []
        scannedFileCount = 0
    }

    private func organize(_ item: LocalMediaOrganizationItem) async throws {
        try await LocalMediaOrganizer.move(item)
    }

    private func repair(_ item: FileDateRepairItem) async throws {
        let isVideo = MediaFileClassifier.isVideo(item.fileURL.lastPathComponent)
        let before = try await MediaMetadataReader.readDateEvidence(url: item.fileURL, isVideo: isVideo)
        guard let freshItem = FileDateRepairPlanner.makeItem(
            fileURL: item.fileURL,
            relativePath: item.relativePath,
            evidence: before
        ), abs(freshItem.currentCreationDate.timeIntervalSince(item.currentCreationDate)) <=
            FileDateRepairPlanner.timestampTolerance,
            abs(freshItem.proposedDate.timeIntervalSince(item.proposedDate)) <=
            FileDateRepairPlanner.timestampTolerance else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSLocalizedDescriptionKey: "Dates changed since the scan. Rescan before repairing."]
            )
        }
        guard let originalModification = before.first(where: {
            $0.source == .filesystemModification
        })?.date else {
            throw CocoaError(
                .fileReadUnknown,
                userInfo: [NSLocalizedDescriptionKey: "The modification date could not be read safely."]
            )
        }

        let embeddedSources = Set(
            before.lazy.filter(\.source.isEmbeddedCreationDate).map(\.source)
        )
        let embeddedNeedsSync = FileDateRepairPlanner.embeddedCreationDatesNeedSync(
            before,
            target: item.proposedDate
        )
        let backupURL = try makeBackup(of: item.fileURL)
        defer { try? FileManager.default.removeItem(at: backupURL) }

        try Task.checkCancellation()
        do {
            try await synchronizeEmbeddedDates(
                for: item,
                isVideo: isVideo,
                isRequired: embeddedNeedsSync
            )
            try Task.checkCancellation()
            try FileDatePreservation.applyFileDates(
                to: item.fileURL,
                created: item.proposedDate,
                modified: item.proposedDate
            )
            let after = try await MediaMetadataReader.readDateEvidence(
                url: item.fileURL,
                isVideo: isVideo
            )
            try Task.checkCancellation()
            if let failure = FileDateRepairVerification.validate(
                after,
                expectedEmbeddedSources: embeddedNeedsSync ? embeddedSources : [],
                target: item.proposedDate
            ) {
                throw CocoaError(
                    .fileWriteUnknown,
                    userInfo: [NSLocalizedDescriptionKey: failure.message]
                )
            }
        } catch {
            do {
                try restoreBackup(
                    backupURL,
                    to: item.fileURL,
                    created: item.currentCreationDate,
                    modified: originalModification
                )
            } catch let rollbackError {
                throw CocoaError(
                    .fileWriteUnknown,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "\(error.localizedDescription) Rollback also failed: \(rollbackError.localizedDescription)"
                    ]
                )
            }
            throw error
        }
    }

    private func synchronizeEmbeddedDates(
        for item: FileDateRepairItem,
        isVideo: Bool,
        isRequired: Bool
    ) async throws {
        guard isRequired else { return }
        if isVideo {
            try await VideoMetadataTransfer.synchronizeCreationDates(
                in: item.fileURL,
                to: item.proposedDate
            )
        } else {
            try FileDatePreservation.synchronizeImageCreationDates(
                in: item.fileURL,
                to: item.proposedDate
            )
        }
    }

    private func makeBackup(of fileURL: URL) throws -> URL {
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".date-repair-backup-\(UUID().uuidString)")
            .appendingPathExtension(fileURL.pathExtension)
        try FileManager.default.copyItem(at: fileURL, to: backupURL)
        return backupURL
    }

    private func restoreBackup(
        _ backupURL: URL,
        to fileURL: URL,
        created: Date,
        modified: Date
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
        try fileManager.moveItem(at: backupURL, to: fileURL)
        try FileDatePreservation.restoreFileDates(
            created: created,
            modified: modified,
            to: fileURL
        )
    }
}

extension LocalPhotosService {
    func convertAll() {
        guard !isRunning, !conversionItems.isEmpty, let directory else { return }
        let plannedItems = conversionItems
        isConverting = true
        cancellationMessage = nil
        conversionSummary = LocalMediaConversionSummary(total: plannedItems.count)
        conversionProgress = FileDateRepairProgress(total: plannedItems.count)
        let operationID = UUID()
        self.operationID = operationID

        operationTask = Task { [weak self] in
            guard let self else { return }
            let didAccess = directory.startAccessingSecurityScopedResource()
            defer {
                if didAccess { directory.stopAccessingSecurityScopedResource() }
                if self.operationID == operationID {
                    isConverting = false
                    operationTask = nil
                    self.operationID = nil
                }
            }

            var summary = LocalMediaConversionSummary(total: plannedItems.count)
            var conversionFailures: [FileDateRepairFailure] = []
            var convertedKeptSources = Set<String>()
            for (index, item) in plannedItems.enumerated() {
                guard !Task.isCancelled, self.operationID == operationID else {
                    summary.wasCancelled = true
                    conversionSummary = summary
                    return
                }
                conversionProgress = FileDateRepairProgress(
                    processed: index,
                    total: plannedItems.count,
                    currentPath: item.sourceRelativePath
                )
                do {
                    try await LocalMediaConverter.convert(item)
                    summary.converted += 1
                    if item.keepOriginal {
                        convertedKeptSources.insert(item.sourceRelativePath)
                    }
                } catch is CancellationError {
                    summary.wasCancelled = true
                    conversionSummary = summary
                    return
                } catch {
                    summary.failed += 1
                    conversionFailures.append(
                        FileDateRepairFailure(
                            relativePath: item.sourceRelativePath,
                            message: error.localizedDescription
                        )
                    )
                }
                conversionProgress.processed = index + 1
                conversionSummary = summary
            }

            guard !Task.isCancelled, self.operationID == operationID else {
                summary.wasCancelled = true
                conversionSummary = summary
                return
            }
            conversionProgress.currentPath = "Refreshing previews…"
            do {
                let refreshed = try await FileDateRepairScanner.scan(
                    directory: directory,
                    supportedExtensions: FileDateRepairExtensions.parse(AppSettings.localMediaExtensions),
                    conversionConfig: AppSettings.localMediaConversionConfig,
                    progress: { _ in }
                )
                guard self.operationID == operationID else { return }
                conversionItems = refreshed.conversionItems.filter {
                    !convertedKeptSources.contains($0.sourceRelativePath)
                }
                items = refreshed.items
                organizationItems = refreshed.organizationItems
                organizationSkippedCount = refreshed.organizationSkippedCount
                failures = conversionFailures + refreshed.failures
                scannedFileCount = refreshed.scannedFileCount
            } catch is CancellationError {
                summary.wasCancelled = true
            } catch {
                conversionFailures.append(
                    FileDateRepairFailure(
                        relativePath: directory.lastPathComponent,
                        message: "Conversion finished, but previews could not refresh: \(error.localizedDescription)"
                    )
                )
                failures = conversionFailures
            }
            conversionSummary = summary
        }
    }
}
