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
    @Published private(set) var progress: DroneFinalizeProgress?
    @Published private(set) var failures: [OrganizeFailure] = []
    @Published private(set) var isRunning = false
    @Published private(set) var previewPlan: DroneFinalizePlan?
    @Published private(set) var previewError: String?
    @Published private(set) var projectDirectoryPath: String?

    private var task: Task<Void, Never>?
    private var onFinished: (@MainActor () async -> Void)?

    func reset() {
        cancel()
        progress = nil
        failures = []
        previewPlan = nil
        previewError = nil
        projectDirectoryPath = nil
    }

    /// Scans the chosen project's export folder and builds a (non-destructive) preview plan.
    func loadPreview(projectDirectory: URL, config: DroneFinalizeConfig) {
        previewError = nil
        previewPlan = nil
        progress = nil
        failures = []
        projectDirectoryPath = projectDirectory.path

        let didAccess = projectDirectory.startAccessingSecurityScopedResource()
        defer { if didAccess { projectDirectory.stopAccessingSecurityScopedResource() } }

        let exportDir = projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
        guard isDirectory(exportDir) else {
            previewError = "No “\(config.exportDirectoryName)” folder found in the selected project folder."
            return
        }

        do {
            let files = try regularFileNames(in: exportDir)
            previewPlan = DroneFinalizePlanBuilder.makePlan(
                exportFiles: files,
                config: config,
                isMedia: { MediaFileClassifier.isMedia($0) }
            )
        } catch {
            previewError = error.localizedDescription
        }
    }

    func finalize(
        projectDirectory: URL,
        config: DroneFinalizeConfig,
        onFinished: (@MainActor () async -> Void)? = nil
    ) {
        guard let plan = previewPlan else { return }
        cancel()
        failures = []
        isRunning = true
        self.onFinished = onFinished

        let total = plan.matchedPairs.count
            + plan.unmatchedCompressed.count
            + plan.finalMediaNames.count
            + 2 // remove raw + export directories
        progress = DroneFinalizeProgress.initial(total: max(total, 1))

        task = Task {
            await run(projectDirectory: projectDirectory, config: config, plan: plan)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning, let current = progress {
            progress = DroneFinalizeProgress(
                current: current.current,
                total: current.total,
                detail: current.detail,
                processedCount: current.processedCount,
                movedCount: current.movedCount,
                failedCount: current.failedCount,
                isComplete: true,
                wasCancelled: true
            )
        }
        isRunning = false
    }

    private func run(projectDirectory: URL, config: DroneFinalizeConfig, plan: DroneFinalizePlan) async {
        let didAccess = projectDirectory.startAccessingSecurityScopedResource()
        defer { if didAccess { projectDirectory.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let exportDir = projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
        let rawDir = projectDirectory.appendingPathComponent(config.rawDirectoryName, isDirectory: true)

        var step = 0
        var processed = 0
        var moved = 0
        var failed = 0
        var failureList: [OrganizeFailure] = []

        func advance(detail: String) {
            step += 1
            progress = DroneFinalizeProgress(
                current: step,
                total: progress?.total ?? step,
                detail: detail,
                processedCount: processed,
                movedCount: moved,
                failedCount: failed,
                isComplete: false,
                wasCancelled: false
            )
        }

        // 1. Matched pairs: copy metadata, delete source, drop suffix.
        for pair in plan.matchedPairs {
            if Task.isCancelled { break }
            advance(detail: pair.compressedName)

            let sourceURL = exportDir.appendingPathComponent(pair.sourceName)
            let compressedURL = exportDir.appendingPathComponent(pair.compressedName)
            let finalURL = exportDir.appendingPathComponent(pair.finalName)

            if MediaFileClassifier.isVideo(pair.compressedName) {
                do {
                    try await VideoMetadataTransfer.transfer(from: sourceURL, to: compressedURL)
                } catch {
                    failureList.append(
                        OrganizeFailure(
                            filename: pair.compressedName,
                            message: "Container metadata not copied (\(error.localizedDescription)); file dates still applied."
                        )
                    )
                }
            }

            do {
                try FileDatePreservation.copyFileDates(from: sourceURL, to: compressedURL)
                try fileManager.removeItem(at: sourceURL)
                try fileManager.moveItem(at: compressedURL, to: finalURL)
                processed += 1
            } catch {
                failed += 1
                failureList.append(OrganizeFailure(filename: pair.compressedName, message: error.localizedDescription))
            }
        }

        // 2. Unmatched compressed: just drop the suffix.
        for item in plan.unmatchedCompressed {
            if Task.isCancelled { break }
            advance(detail: item.originalName)

            let originalURL = exportDir.appendingPathComponent(item.originalName)
            let finalURL = exportDir.appendingPathComponent(item.finalName)
            do {
                try fileManager.moveItem(at: originalURL, to: finalURL)
                processed += 1
                failureList.append(
                    OrganizeFailure(
                        filename: item.originalName,
                        message: "No source original found; renamed without metadata copy."
                    )
                )
            } catch {
                failed += 1
                failureList.append(OrganizeFailure(filename: item.originalName, message: error.localizedDescription))
            }
        }

        // 3. Move all remaining media up one level into the project root.
        if !Task.isCancelled {
            for name in plan.finalMediaNames.sorted() {
                if Task.isCancelled { break }
                advance(detail: "Moving \(name)")
                let fromURL = exportDir.appendingPathComponent(name)
                guard fileManager.fileExists(atPath: fromURL.path) else { continue }
                let destination = uniqueDestination(directory: projectDirectory, filename: name, fileManager: fileManager)
                do {
                    try fileManager.moveItem(at: fromURL, to: destination)
                    moved += 1
                } catch {
                    failed += 1
                    failureList.append(OrganizeFailure(filename: name, message: error.localizedDescription))
                }
            }
        }

        // 4. Remove raw + export directories so only the flat media remains.
        if !Task.isCancelled {
            advance(detail: "Removing \(config.rawDirectoryName)/")
            if fileManager.fileExists(atPath: rawDir.path) {
                do {
                    try fileManager.removeItem(at: rawDir)
                } catch {
                    failed += 1
                    failureList.append(OrganizeFailure(filename: config.rawDirectoryName, message: error.localizedDescription))
                }
            }

            advance(detail: "Removing \(config.exportDirectoryName)/")
            do {
                try fileManager.removeItem(at: exportDir)
            } catch {
                failed += 1
                failureList.append(OrganizeFailure(filename: config.exportDirectoryName, message: error.localizedDescription))
            }
        }

        let cancelled = Task.isCancelled
        let finished = onFinished
        onFinished = nil

        failures = failureList
        progress = DroneFinalizeProgress(
            current: progress?.total ?? step,
            total: progress?.total ?? step,
            detail: "",
            processedCount: processed,
            movedCount: moved,
            failedCount: failed,
            isComplete: true,
            wasCancelled: cancelled
        )
        isRunning = false
        task = nil
        previewPlan = nil

        if !cancelled {
            await finished?()
        }
    }

    // MARK: - Helpers

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func regularFileNames(in directory: URL) throws -> [String] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        )
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return (values?.isRegularFile ?? false) ? url.lastPathComponent : nil
        }
    }

    private func uniqueDestination(directory: URL, filename: String, fileManager: FileManager) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 1
        repeat {
            let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }
}
