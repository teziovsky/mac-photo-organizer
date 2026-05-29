import Foundation

/// User-configurable inputs for the drone finalize workflow.
struct DroneFinalizeConfig: Equatable, Sendable {
    var compressedSuffix: String
    var rawDirectoryName: String
    var exportDirectoryName: String

    static let `default` = DroneFinalizeConfig(
        compressedSuffix: "_COMPRESSED",
        rawDirectoryName: "raw",
        exportDirectoryName: "export"
    )

    /// Trimmed suffix; falls back to the default when blank.
    var normalizedSuffix: String {
        let trimmed = compressedSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "_COMPRESSED" : trimmed
    }
}

/// A compressed file matched to its source original.
struct DroneMatchedPair: Equatable, Sendable {
    let sourceName: String
    let compressedName: String
    let finalName: String
}

/// A compressed file whose suffix is dropped, with no matching source (no delete, no metadata copy).
struct DroneRenameOnly: Equatable, Sendable {
    let originalName: String
    let finalName: String
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

    /// Every media filename that will exist in the export dir after pairs are processed,
    /// i.e. the set that gets moved up one level into the project root.
    var finalMediaNames: [String] {
        var names = matchedPairs.map(\.finalName)
        names.append(contentsOf: unmatchedCompressed.map(\.finalName))
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
    /// Builds a plan from the regular (non-directory) file names in the export directory.
    /// `isMedia` decides whether a leftover (no compressed counterpart) is moved up or reported.
    static func makePlan(
        exportFiles files: [String],
        config: DroneFinalizeConfig,
        isMedia: (String) -> Bool
    ) -> DroneFinalizePlan {
        let suffix = config.normalizedSuffix

        // Ignore hidden files (e.g. .DS_Store) entirely; they neither move nor block.
        let visible = files.filter { !$0.hasPrefix(".") }

        let compressed = visible.filter { hasCompressedSuffix($0, suffix: suffix) }
        let compressedSet = Set(compressed)

        // Lookup of non-compressed files by their base name (without extension), lowercased.
        var candidatesByBase: [String: [String]] = [:]
        for file in visible where !compressedSet.contains(file) {
            let base = baseName(file).lowercased()
            candidatesByBase[base, default: []].append(file)
        }

        var plan = DroneFinalizePlan()
        var consumedSources = Set<String>()
        var claimedFinalNames = Set<String>()

        for compressedFile in compressed.sorted() {
            let strippedBase = strippingCompressedSuffix(baseName(compressedFile), suffix: suffix)
            let ext = fileExtension(compressedFile)
            let finalName = ext.isEmpty ? strippedBase : "\(strippedBase).\(ext)"
            let finalKey = finalName.lowercased()

            // Source: a non-compressed file sharing the stripped base name, not already used.
            let source = (candidatesByBase[strippedBase.lowercased()] ?? [])
                .filter { !consumedSources.contains($0) }
                .sorted()
                .first

            // Collision: final name already claimed, or matches an unrelated existing file.
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
                        sourceName: source,
                        compressedName: compressedFile,
                        finalName: finalName
                    )
                )
            } else {
                plan.unmatchedCompressed.append(
                    DroneRenameOnly(originalName: compressedFile, finalName: finalName)
                )
            }
        }

        // Remaining non-compressed files that were not consumed as a source.
        for file in visible where !compressedSet.contains(file) && !consumedSources.contains(file) {
            if isMedia(file) {
                plan.passthroughMedia.append(file)
            } else {
                plan.leftoverFiles.append(file)
            }
        }

        plan.matchedPairs.sort { $0.compressedName < $1.compressedName }
        plan.unmatchedCompressed.sort { $0.originalName < $1.originalName }
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
}
