import Foundation

/// Collects regular files under a directory tree as paths relative to the root.
enum DroneMediaPaths {
    static func regularFiles(relativeTo directory: URL, fileManager: FileManager = .default) throws -> [String] {
        var results: [String] = []
        try collect(from: directory, prefix: "", into: &results, fileManager: fileManager)
        return results.sorted()
    }

    static func exportURL(project: URL, config: DroneFinalizeConfig, relativePath: String) -> URL {
        project
            .appendingPathComponent(config.exportDirectoryName, isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    static func flattenDestination(
        project: URL,
        relativeMediaPath: String,
        config: DroneFinalizeConfig,
        fileManager: FileManager = .default
    ) -> URL {
        if config.preserveOrientationOnFlatten {
            let destination = project.appendingPathComponent(relativeMediaPath)
            return uniqueFileURL(base: destination, fileManager: fileManager)
        }
        let filename = (relativeMediaPath as NSString).lastPathComponent
        return uniqueFileURL(
            base: project.appendingPathComponent(filename),
            fileManager: fileManager
        )
    }

    private static func collect(
        from directory: URL,
        prefix: String,
        into results: inout [String],
        fileManager: FileManager
    ) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in urls.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = url.lastPathComponent
            let relative = prefix.isEmpty ? name : "\(prefix)/\(name)"
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values.isDirectory == true {
                try collect(from: url, prefix: relative, into: &results, fileManager: fileManager)
            } else if values.isRegularFile == true {
                results.append(relative)
            }
        }
    }

    private static func uniqueFileURL(base: URL, fileManager: FileManager) -> URL {
        var candidate = base
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let filename = base.lastPathComponent
        let directory = base.deletingLastPathComponent()
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 1
        repeat {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }
}
