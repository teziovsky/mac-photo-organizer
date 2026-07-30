import Foundation

struct FileDateScanOutput: Sendable {
    let relativePath: String
    let item: FileDateRepairItem?
    let failure: FileDateRepairFailure?
}

struct FileDateScanResult: Sendable {
    let items: [FileDateRepairItem]
    let failures: [FileDateRepairFailure]
    let scannedFileCount: Int
}

enum FileDateRepairScanner {
    static let maximumConcurrentReads = 8

    static func scan(
        directory: URL,
        supportedExtensions: Set<String>,
        progress: @escaping @Sendable (FileDateRepairProgress) async -> Void
    ) async throws -> FileDateScanResult {
        let enumeration = try enumerateFiles(in: directory, supportedExtensions: supportedExtensions)
        var failures = enumeration.failures
        var items: [FileDateRepairItem] = []
        var nextIndex = 0
        var processed = 0

        try await withThrowingTaskGroup(of: FileDateScanOutput.self) { group in
            func addNext() {
                guard nextIndex < enumeration.files.count else { return }
                let file = enumeration.files[nextIndex]
                nextIndex += 1
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let isVideo = MediaFileClassifier.isVideo(file.url.lastPathComponent)
                        let evidence = try await MediaMetadataReader.readDateEvidence(
                            url: file.url,
                            isVideo: isVideo
                        )
                        let item = FileDateRepairPlanner.makeItem(
                            fileURL: file.url,
                            relativePath: file.relativePath,
                            evidence: evidence
                        )
                        return FileDateScanOutput(relativePath: file.relativePath, item: item, failure: nil)
                    } catch {
                        return FileDateScanOutput(
                            relativePath: file.relativePath,
                            item: nil,
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
                if let item = output.item { items.append(item) }
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
            items: items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending },
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

@MainActor
final class FileDateRepairService: ObservableObject {
    @Published private(set) var directory: URL?
    @Published private(set) var items: [FileDateRepairItem] = []
    @Published private(set) var failures: [FileDateRepairFailure] = []
    @Published private(set) var progress = FileDateRepairProgress()
    @Published private(set) var isScanning = false
    @Published private(set) var isRepairing = false
    @Published private(set) var repairedIDs: Set<String> = []
    @Published private(set) var attemptedIDs: Set<String> = []
    @Published private(set) var scannedFileCount = 0
    @Published var chunkSize = 100

    private var operationTask: Task<Void, Never>?
    private var operationID: UUID?

    var isRunning: Bool { isScanning || isRepairing }

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
        let extensions = FileDateRepairExtensions.parse(AppSettings.fileDateRepairExtensions)
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
                    supportedExtensions: extensions
                ) { progress in
                    await MainActor.run {
                        if self.operationID == operationID {
                            self.progress = progress
                        }
                    }
                }
                try Task.checkCancellation()
                guard self.operationID == operationID else { return }
                items = result.items
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
        guard !isRunning, !currentChunk.isEmpty, let directory else { return }
        let chunk = currentChunk
        isRepairing = true
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

    func cancel() {
        operationTask?.cancel()
        operationTask = nil
        operationID = nil
        isScanning = false
        isRepairing = false
    }

    func reset() {
        cancel()
        directory = nil
        resetResults()
    }

    private func resetResults() {
        items = []
        failures = []
        progress = FileDateRepairProgress()
        repairedIDs = []
        attemptedIDs = []
        scannedFileCount = 0
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
            abs(freshItem.proposedCreationDate.timeIntervalSince(item.proposedCreationDate)) <=
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

        try Task.checkCancellation()
        do {
            try FileDatePreservation.applyCreationDate(item.proposedCreationDate, to: item.fileURL)
            let created = try item.fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate
            guard let created,
                  abs(created.timeIntervalSince(item.proposedCreationDate)) <=
                    FileDateRepairPlanner.timestampTolerance else {
                throw CocoaError(
                    .fileWriteUnknown,
                    userInfo: [NSLocalizedDescriptionKey: "The creation date could not be verified after writing."]
                )
            }
        } catch {
            do {
                try FileDatePreservation.restoreFileDates(
                    created: item.currentCreationDate,
                    modified: originalModification,
                    to: item.fileURL
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
}
