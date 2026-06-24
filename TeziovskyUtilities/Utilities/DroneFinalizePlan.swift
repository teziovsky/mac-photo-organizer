import Foundation

/// User-configurable inputs for the drone project workflow.
struct DroneFinalizeConfig: Equatable, Sendable {
    var compressedSuffix: String
    var rawDirectoryName: String
    var exportDirectoryName: String
    var verticalDirectoryName: String
    var horizontalDirectoryName: String
    var handBrakeCLIPath: String
    var resolveAppPath: String
    var handBrakeOutputExtension: String
    var keepRawAfterFinalize: Bool
    var preserveOrientationOnFlatten: Bool

    static let `default` = DroneFinalizeConfig(
        compressedSuffix: "_COMPRESSED",
        rawDirectoryName: "raw",
        exportDirectoryName: "export",
        verticalDirectoryName: "vertical",
        horizontalDirectoryName: "horizontal",
        handBrakeCLIPath: "",
        resolveAppPath: "",
        handBrakeOutputExtension: "mp4",
        keepRawAfterFinalize: true,
        preserveOrientationOnFlatten: true
    )

    /// Trimmed suffix; falls back to the default when blank.
    var normalizedSuffix: String {
        let trimmed = compressedSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "_COMPRESSED" : trimmed
    }

    var normalizedOutputExtension: String {
        let trimmed = handBrakeOutputExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "mp4" : trimmed.lowercased()
    }
}

/// A compressed file matched to its source original.
struct DroneMatchedPair: Equatable, Sendable {
    let sourceRelativePath: String
    let compressedRelativePath: String
    let finalRelativePath: String

    /// Backward-compatible flat filename accessors for UI/tests using root-level paths.
    var sourceName: String { sourceRelativePath }
    var compressedName: String { compressedRelativePath }
    var finalName: String { finalRelativePath }
}

/// A compressed file whose suffix is dropped, with no matching source (no delete, no metadata copy).
struct DroneRenameOnly: Equatable, Sendable {
    let originalRelativePath: String
    let finalRelativePath: String

    var originalName: String { originalRelativePath }
    var finalName: String { finalRelativePath }
}

/// Pure description of what the finalize run will do to the export directory.
/// Built without touching the filesystem so it can be previewed and unit-tested.
struct DroneFinalizePlan: Equatable, Sendable {
    var matchedPairs: [DroneMatchedPair] = []
    var unmatchedCompressed: [DroneRenameOnly] = []
    /// Media files (no compressed suffix, not consumed as a source) kept and moved up.
    var passthroughMedia: [String] = []
    /// Non-media files left in the export dir (reported; removed with the dir).
    var leftoverFiles: [String] = []
    /// Compressed files skipped because their final name would collide with another file.
    var conflicts: [String] = []

    /// Every media relative path that will exist in the export dir after pairs are processed.
    var finalMediaNames: [String] {
        var names = matchedPairs.map(\.finalRelativePath)
        names.append(contentsOf: unmatchedCompressed.map(\.finalRelativePath))
        names.append(contentsOf: passthroughMedia)
        return names
    }

    var hasWork: Bool {
        !matchedPairs.isEmpty
            || !unmatchedCompressed.isEmpty
            || !passthroughMedia.isEmpty
    }
}

enum DroneFinalizePlanBuilder {
    /// Builds a plan from relative file paths under the export directory.
    /// `isMedia` receives the filename (last path component) only.
    static func makePlan(
        exportFiles files: [String],
        config: DroneFinalizeConfig,
        isMedia: (String) -> Bool
    ) -> DroneFinalizePlan {
        let suffix = config.normalizedSuffix
        let visible = files.filter { !$0.hasPrefix(".") && !($0 as NSString).lastPathComponent.hasPrefix(".") }

        let compressed = visible.filter { hasCompressedSuffix(($0 as NSString).lastPathComponent, suffix: suffix) }
        let compressedSet = Set(compressed)

        var candidatesByDirectoryAndBase: [String: [String]] = [:]
        for file in visible where !compressedSet.contains(file) {
            let directory = directoryPrefix(of: file)
            let base = baseName((file as NSString).lastPathComponent).lowercased()
            let key = "\(directory)|\(base)"
            candidatesByDirectoryAndBase[key, default: []].append(file)
        }

        var plan = DroneFinalizePlan()
        var consumedSources = Set<String>()
        var claimedFinalNames = Set<String>()

        for compressedFile in compressed.sorted() {
            let fileName = (compressedFile as NSString).lastPathComponent
            let directory = directoryPrefix(of: compressedFile)
            let strippedBase = strippingCompressedSuffix(baseName(fileName), suffix: suffix)
            let ext = fileExtension(fileName)
            let finalFileName = ext.isEmpty ? strippedBase : "\(strippedBase).\(ext)"
            let finalRelativePath = directory.isEmpty ? finalFileName : "\(directory)/\(finalFileName)"
            let finalKey = finalRelativePath.lowercased()

            let lookupKey = "\(directory)|\(strippedBase.lowercased())"
            let source = (candidatesByDirectoryAndBase[lookupKey] ?? [])
                .filter { !consumedSources.contains($0) }
                .sorted()
                .first

            let collidesWithExisting = visible.contains {
                $0.lowercased() == finalKey
                    && $0 != compressedFile
                    && $0 != source
            }
            if claimedFinalNames.contains(finalKey) || collidesWithExisting {
                plan.conflicts.append(compressedFile)
                continue
            }

            claimedFinalNames.insert(finalKey)

            if let source {
                consumedSources.insert(source)
                plan.matchedPairs.append(
                    DroneMatchedPair(
                        sourceRelativePath: source,
                        compressedRelativePath: compressedFile,
                        finalRelativePath: finalRelativePath
                    )
                )
            } else {
                plan.unmatchedCompressed.append(
                    DroneRenameOnly(
                        originalRelativePath: compressedFile,
                        finalRelativePath: finalRelativePath
                    )
                )
            }
        }

        for file in visible where !compressedSet.contains(file) && !consumedSources.contains(file) {
            let fileName = (file as NSString).lastPathComponent
            if isMedia(fileName) {
                plan.passthroughMedia.append(file)
            } else {
                plan.leftoverFiles.append(file)
            }
        }

        plan.matchedPairs.sort { $0.compressedRelativePath < $1.compressedRelativePath }
        plan.unmatchedCompressed.sort { $0.originalRelativePath < $1.originalRelativePath }
        plan.passthroughMedia.sort()
        plan.leftoverFiles.sort()
        plan.conflicts.sort()
        return plan
    }

    static func hasCompressedSuffix(_ filename: String, suffix: String) -> Bool {
        baseName(filename).hasSuffix(suffix) && baseName(filename) != suffix
    }

    static func strippingCompressedSuffix(_ base: String, suffix: String) -> String {
        guard base.hasSuffix(suffix), base != suffix else { return base }
        return String(base.dropLast(suffix.count))
    }

    static func baseName(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }

    static func fileExtension(_ filename: String) -> String {
        (filename as NSString).pathExtension
    }

    private static func directoryPrefix(of relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        if directory == "." { return "" }
        return directory
    }
}

enum DroneToolPaths {
    static func resolveHandBrakeCLI(configuredPath: String) -> URL? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }
        let candidates = [
            "/opt/homebrew/bin/HandBrakeCLI",
            "/usr/local/bin/HandBrakeCLI",
            "/Applications/HandBrake.app/Contents/MacOS/HandBrakeCLI"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func resolveDaVinciResolve(configuredPath: String) -> URL? {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }
        let candidates = [
            "/Applications/DaVinci Resolve/DaVinci Resolve.app",
            "/Applications/DaVinci Resolve.app"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}
