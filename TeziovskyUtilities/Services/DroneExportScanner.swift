import Foundation

struct DroneUncompressedExport: Identifiable, Equatable, Sendable {
    let id: String
    let relativePath: String
    let fileSizeBytes: Int64?

    var fileName: String { (relativePath as NSString).lastPathComponent }
    var orientationFolder: String? {
        let directory = (relativePath as NSString).deletingLastPathComponent
        guard !directory.isEmpty, directory != "." else { return nil }
        return directory
    }
}

enum DroneExportScanner {
    static func uncompressedExports(
        projectDirectory: URL,
        config: DroneFinalizeConfig,
        isMedia: (String) -> Bool = { MediaFileClassifier.isMedia($0) }
    ) throws -> [DroneUncompressedExport] {
        let exportDir = projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true)
        let files = try DroneMediaPaths.regularFiles(relativeTo: exportDir)
        let suffix = config.normalizedSuffix
        let fileSet = Set(files.map { $0.lowercased() })

        return files.compactMap { relativePath in
            let fileName = (relativePath as NSString).lastPathComponent
            guard isMedia(fileName) else { return nil }
            guard !DroneFinalizePlanBuilder.hasCompressedSuffix(fileName, suffix: suffix) else { return nil }

            let compressedRelative = compressedRelativePath(for: relativePath, config: config)
            if fileSet.contains(compressedRelative.lowercased()) { return nil }

            let url = exportDir.appendingPathComponent(relativePath)
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
            return DroneUncompressedExport(
                id: relativePath,
                relativePath: relativePath,
                fileSizeBytes: size
            )
        }
    }

    static func compressedRelativePath(for relativePath: String, config: DroneFinalizeConfig) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        let fileName = (relativePath as NSString).lastPathComponent
        let base = DroneFinalizePlanBuilder.baseName(fileName)
        let outputName = "\(base)\(config.normalizedSuffix).\(config.normalizedOutputExtension)"
        if directory.isEmpty || directory == "." { return outputName }
        return "\(directory)/\(outputName)"
    }
}
