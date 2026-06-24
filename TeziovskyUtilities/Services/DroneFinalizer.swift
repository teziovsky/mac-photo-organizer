import Foundation
import UniformTypeIdentifiers

/// Classifies files as media using UniformTypeIdentifiers.
enum MediaFileClassifier {
    static func isMedia(_ filename: String) -> Bool {
        guard let type = utType(for: filename) else { return false }
        return type.conforms(to: .image)
            || type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
    }

    static func isVideo(_ filename: String) -> Bool {
        guard let type = utType(for: filename) else { return false }
        return type.conforms(to: .movie)
            || type.conforms(to: .audiovisualContent)
            || type.conforms(to: .video)
    }

    private static func utType(for filename: String) -> UTType? {
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }
}

@MainActor
final class DroneFinalizer: ObservableObject {
    /// A single reversible filesystem change recorded so a step can be undone.
    private enum ReversibleOp {
        case restoreFile(target: URL, backup: URL)
        case restoreDates(url: URL, creation: Date?, modification: Date?)
        case move(from: URL, to: URL)
        case untrash(original: URL, trashed: URL)
    }

    private struct StepRecord {
        let step: DroneFinalizeStep
        let ops: [ReversibleOp]
    }

    @Published private(set) var step: DroneFinalizeStep = .merge
    @Published private(set) var plan: DroneFinalizePlan?
    @Published private(set) var pairMetadata: [DronePairMetadata] = []
    @Published private(set) var previewError: String?
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var failures: [OrganizeFailure] = []
    @Published private(set) var canUndo = false
    @Published private(set) var projectDirectoryPath: String?

    private(set) var config: DroneFinalizeConfig = .default
    private var projectDirectory: URL?
    private var undoStack: [StepRecord] = []
    private var backupDirectory: URL?

    var hasProject: Bool { projectDirectory != nil }

    // MARK: - Setup

    func loadProject(projectDirectory: URL, config: DroneFinalizeConfig) {
        reset(keepingProject: false)
        self.config = config
        self.projectDirectory = projectDirectory
        projectDirectoryPath = projectDirectory.path

        let didAccess = projectDirectory.startAccessingSecurityScopedResource()
        defer { if didAccess { projectDirectory.stopAccessingSecurityScopedResource() } }

        let exportDir = projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
        guard isDirectory(exportDir) else {
            previewError = "No “\(config.exportDirectoryName)” folder found in the selected project folder."
            return
        }

        do {
            let files = try DroneMediaPaths.regularFiles(relativeTo: exportDir)
            let plan = DroneFinalizePlanBuilder.makePlan(
                exportFiles: files,
                config: config,
                isMedia: { MediaFileClassifier.isMedia($0) }
            )
            self.plan = plan
            pairMetadata = plan.matchedPairs.map { pair in
                DronePairMetadata(
                    id: pair.compressedRelativePath,
                    sourceName: pair.sourceRelativePath,
                    compressedName: pair.compressedRelativePath,
                    finalName: pair.finalRelativePath,
                    isVideo: MediaFileClassifier.isVideo((pair.compressedRelativePath as NSString).lastPathComponent)
                )
            }
            step = .merge
            loadMetadata()
        } catch {
            previewError = error.localizedDescription
        }
    }

    func reset(keepingProject: Bool = false) {
        cleanUpBackups()
        if !keepingProject {
            projectDirectory = nil
            projectDirectoryPath = nil
        }
        plan = nil
        pairMetadata = []
        previewError = nil
        statusMessage = nil
        failures = []
        undoStack = []
        canUndo = false
        isRunning = false
        step = .merge
        if !keepingProject {
            config = .default
        }
    }

    func reset() {
        reset(keepingProject: false)
    }

    private func loadMetadata() {
        guard let project = projectDirectory, let plan else { return }
        let exportDir = project.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
        let pairs = plan.matchedPairs
        Task {
            let didAccess = project.startAccessingSecurityScopedResource()
            defer { if didAccess { project.stopAccessingSecurityScopedResource() } }
            for pair in pairs {
                let fileName = (pair.compressedRelativePath as NSString).lastPathComponent
                let isVideo = MediaFileClassifier.isVideo(fileName)
                let original = await MediaMetadataReader.read(
                    url: exportDir.appendingPathComponent(pair.sourceRelativePath),
                    isVideo: MediaFileClassifier.isVideo((pair.sourceRelativePath as NSString).lastPathComponent)
                )
                let compressed = await MediaMetadataReader.read(
                    url: exportDir.appendingPathComponent(pair.compressedRelativePath),
                    isVideo: isVideo
                )
                if let index = pairMetadata.firstIndex(where: { $0.id == pair.compressedRelativePath }) {
                    pairMetadata[index].original = original
                    pairMetadata[index].compressed = compressed
                }
            }
        }
    }

    // MARK: - Steps

    func performCurrentStep() {
        switch step {
        case .merge: performMerge()
        case .cleanup: performCleanup()
        case .flatten: performFlatten()
        case .done: break
        }
    }

    private func performMerge() {
        guard step == .merge, let project = projectDirectory, let plan else { return }
        let exportDir = project.appendingPathComponent(config.exportDirectoryName, isDirectory: true)

        run { [self] in
            var ops: [ReversibleOp] = []
            var issues: [OrganizeFailure] = []
            let fileManager = FileManager.default

            for pair in plan.matchedPairs {
                statusMessage = "Merging \(pair.compressedRelativePath)…"
                let sourceURL = exportDir.appendingPathComponent(pair.sourceRelativePath)
                let compressedURL = exportDir.appendingPathComponent(pair.compressedRelativePath)
                let fileName = (pair.compressedRelativePath as NSString).lastPathComponent

                if MediaFileClassifier.isVideo(fileName) {
                    do {
                        let backupURL = try makeBackup(of: compressedURL, fileManager: fileManager)
                        ops.append(.restoreFile(target: compressedURL, backup: backupURL))
                        try await VideoMetadataTransfer.transfer(from: sourceURL, to: compressedURL)
                    } catch {
                        issues.append(OrganizeFailure(
                            filename: pair.compressedRelativePath,
                            message: "Container metadata not copied (\(error.localizedDescription)); file dates still applied."
                        ))
                    }
                } else if let values = try? compressedURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
                    ops.append(.restoreDates(url: compressedURL, creation: values.creationDate, modification: values.contentModificationDate))
                }

                do {
                    try FileDatePreservation.copyFileDates(from: sourceURL, to: compressedURL)
                } catch {
                    issues.append(OrganizeFailure(filename: pair.compressedRelativePath, message: error.localizedDescription))
                }
            }

            failures = issues
            pushUndo(step: .merge, ops: ops)
            advance(to: .cleanup)
        }
    }

    private func performCleanup() {
        guard step == .cleanup, let project = projectDirectory, let plan else { return }
        let exportDir = project.appendingPathComponent(config.exportDirectoryName, isDirectory: true)

        run { [self] in
            var ops: [ReversibleOp] = []
            var issues: [OrganizeFailure] = []
            let fileManager = FileManager.default

            for pair in plan.matchedPairs {
                statusMessage = "Removing \(pair.sourceRelativePath)…"
                let sourceURL = exportDir.appendingPathComponent(pair.sourceRelativePath)
                let compressedURL = exportDir.appendingPathComponent(pair.compressedRelativePath)
                let finalURL = exportDir.appendingPathComponent(pair.finalRelativePath)
                do {
                    if let trashed = try trash(sourceURL, fileManager: fileManager) {
                        ops.append(.untrash(original: sourceURL, trashed: trashed))
                    }
                    try fileManager.moveItem(at: compressedURL, to: finalURL)
                    ops.append(.move(from: compressedURL, to: finalURL))
                } catch {
                    issues.append(OrganizeFailure(filename: pair.compressedRelativePath, message: error.localizedDescription))
                }
            }

            for item in plan.unmatchedCompressed {
                statusMessage = "Renaming \(item.originalRelativePath)…"
                let originalURL = exportDir.appendingPathComponent(item.originalRelativePath)
                let finalURL = exportDir.appendingPathComponent(item.finalRelativePath)
                do {
                    try fileManager.moveItem(at: originalURL, to: finalURL)
                    ops.append(.move(from: originalURL, to: finalURL))
                } catch {
                    issues.append(OrganizeFailure(filename: item.originalRelativePath, message: error.localizedDescription))
                }
            }

            failures = issues
            pushUndo(step: .cleanup, ops: ops)
            advance(to: .flatten)
        }
    }

    private func performFlatten() {
        guard step == .flatten, let project = projectDirectory, let plan else { return }
        let exportDir = project.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
        let rawDir = project.appendingPathComponent(config.rawDirectoryName, isDirectory: true)

        run { [self] in
            var ops: [ReversibleOp] = []
            var issues: [OrganizeFailure] = []
            let fileManager = FileManager.default

            for relativePath in plan.finalMediaNames.sorted() {
                let fromURL = exportDir.appendingPathComponent(relativePath)
                guard fileManager.fileExists(atPath: fromURL.path) else { continue }
                statusMessage = "Moving \(relativePath)…"
                let destination = DroneMediaPaths.flattenDestination(
                    project: project,
                    relativeMediaPath: relativePath,
                    config: config,
                    fileManager: fileManager
                )
                do {
                    try ensureParentExists(of: destination, fileManager: fileManager)
                    try fileManager.moveItem(at: fromURL, to: destination)
                    ops.append(.move(from: fromURL, to: destination))
                } catch {
                    issues.append(OrganizeFailure(filename: relativePath, message: error.localizedDescription))
                }
            }

            if !config.keepRawAfterFinalize, fileManager.fileExists(atPath: rawDir.path) {
                statusMessage = "Moving \(config.rawDirectoryName)/ to Trash…"
                do {
                    if let trashed = try trash(rawDir, fileManager: fileManager) {
                        ops.append(.untrash(original: rawDir, trashed: trashed))
                    }
                } catch {
                    issues.append(OrganizeFailure(filename: config.rawDirectoryName, message: error.localizedDescription))
                }
            }

            if fileManager.fileExists(atPath: exportDir.path) {
                statusMessage = "Moving \(config.exportDirectoryName)/ to Trash…"
                do {
                    if let trashed = try trash(exportDir, fileManager: fileManager) {
                        ops.append(.untrash(original: exportDir, trashed: trashed))
                    }
                } catch {
                    issues.append(OrganizeFailure(filename: config.exportDirectoryName, message: error.localizedDescription))
                }
            }

            failures = issues
            pushUndo(step: .flatten, ops: ops)
            advance(to: .done)
        }
    }

    // MARK: - Undo

    func goBack() {
        guard let record = undoStack.last, !isRunning else { return }

        run { [self] in
            var issues: [OrganizeFailure] = []
            for op in record.ops.reversed() {
                do {
                    try reverse(op)
                } catch {
                    issues.append(OrganizeFailure(filename: "", message: "Could not undo: \(error.localizedDescription)"))
                }
            }
            failures = issues
            undoStack.removeLast()
            canUndo = !undoStack.isEmpty
            statusMessage = "Reverted \(record.step.shortTitle)."
            step = record.step
            if step == .merge { loadMetadata() }
        }
    }

    private func reverse(_ op: ReversibleOp) throws {
        let fileManager = FileManager.default
        switch op {
        case let .restoreFile(target, backup):
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: backup, to: target)
        case let .restoreDates(url, creation, modification):
            var attributes: [FileAttributeKey: Any] = [:]
            if let creation { attributes[.creationDate] = creation }
            if let modification { attributes[.modificationDate] = modification }
            if !attributes.isEmpty {
                try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
            }
        case let .move(from, to):
            try ensureParentExists(of: from, fileManager: fileManager)
            try fileManager.moveItem(at: to, to: from)
        case let .untrash(original, trashed):
            try ensureParentExists(of: original, fileManager: fileManager)
            try fileManager.moveItem(at: trashed, to: original)
        }
    }

    // MARK: - Helpers

    private func run(_ work: @escaping () async -> Void) {
        guard !isRunning else { return }
        isRunning = true
        failures = []
        statusMessage = nil
        let project = projectDirectory
        Task {
            let didAccess = project?.startAccessingSecurityScopedResource() ?? false
            await work()
            if didAccess { project?.stopAccessingSecurityScopedResource() }
            statusMessage = nil
            isRunning = false
        }
    }

    private func advance(to next: DroneFinalizeStep) {
        step = next
    }

    private func pushUndo(step: DroneFinalizeStep, ops: [ReversibleOp]) {
        undoStack.append(StepRecord(step: step, ops: ops))
        canUndo = true
    }

    private func makeBackup(of url: URL, fileManager: FileManager) throws -> URL {
        let directory = try backupDir(fileManager: fileManager)
        let backupURL = directory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        try fileManager.copyItem(at: url, to: backupURL)
        return backupURL
    }

    private func backupDir(fileManager: FileManager) throws -> URL {
        if let backupDirectory { return backupDirectory }
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("dronefinalize-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        backupDirectory = directory
        return directory
    }

    private func cleanUpBackups() {
        if let backupDirectory {
            try? FileManager.default.removeItem(at: backupDirectory)
            self.backupDirectory = nil
        }
    }

    private func trash(_ url: URL, fileManager: FileManager) throws -> URL? {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    private func ensureParentExists(of url: URL, fileManager: FileManager) throws {
        let parent = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
