import Foundation

enum DroneProjectLayoutMode: Equatable, Sendable {
    case flat
    case oriented(vertical: Bool, horizontal: Bool)
}

struct DroneProjectValidationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case valid
        case validWithWarnings
        case invalid
    }

    let status: Status
    let layoutMode: DroneProjectLayoutMode?
    let messages: [String]
    let treeLines: [String]

    var canContinue: Bool {
        status == .valid || status == .validWithWarnings
    }
}

enum DroneProjectValidator {
    static func validate(projectDirectory: URL, config: DroneFinalizeConfig) -> DroneProjectValidationResult {
        let fileManager = FileManager.default
        var messages: [String] = []
        var treeLines: [String] = ["\(projectDirectory.lastPathComponent)/"]

        let rawDir = projectDirectory.appendingPathComponent(config.rawDirectoryName, isDirectory: true)
        let exportDir = projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true)

        guard isDirectory(rawDir, fileManager: fileManager) else {
            return invalid(
                messages: ["Missing required “\(config.rawDirectoryName)/” folder."],
                treeLines: treeLines
            )
        }
        treeLines.append("├── \(config.rawDirectoryName)/")

        guard isDirectory(exportDir, fileManager: fileManager) else {
            return invalid(
                messages: ["Missing required “\(config.exportDirectoryName)/” folder."],
                treeLines: treeLines
            )
        }
        treeLines.append("└── \(config.exportDirectoryName)/")

        let rawVertical = isDirectory(rawDir.appendingPathComponent(config.verticalDirectoryName, isDirectory: true), fileManager: fileManager)
        let rawHorizontal = isDirectory(rawDir.appendingPathComponent(config.horizontalDirectoryName, isDirectory: true), fileManager: fileManager)
        let exportVertical = isDirectory(exportDir.appendingPathComponent(config.verticalDirectoryName, isDirectory: true), fileManager: fileManager)
        let exportHorizontal = isDirectory(exportDir.appendingPathComponent(config.horizontalDirectoryName, isDirectory: true), fileManager: fileManager)

        let usesOrientation = rawVertical || rawHorizontal || exportVertical || exportHorizontal
        let layoutMode: DroneProjectLayoutMode = usesOrientation
            ? .oriented(vertical: rawVertical || exportVertical, horizontal: rawHorizontal || exportHorizontal)
            : .flat

        if usesOrientation {
            appendOrientationTree(
                to: &treeLines,
                rawVertical: rawVertical,
                rawHorizontal: rawHorizontal,
                exportVertical: exportVertical,
                exportHorizontal: exportHorizontal,
                config: config
            )

            if rawVertical && !exportVertical {
                messages.append("“\(config.rawDirectoryName)/\(config.verticalDirectoryName)/” exists but “\(config.exportDirectoryName)/\(config.verticalDirectoryName)/” is missing.")
            }
            if exportVertical && !rawVertical {
                messages.append("“\(config.exportDirectoryName)/\(config.verticalDirectoryName)/” exists but “\(config.rawDirectoryName)/\(config.verticalDirectoryName)/” is missing.")
            }
            if rawHorizontal && !exportHorizontal {
                messages.append("“\(config.rawDirectoryName)/\(config.horizontalDirectoryName)/” exists but “\(config.exportDirectoryName)/\(config.horizontalDirectoryName)/” is missing.")
            }
            if exportHorizontal && !rawHorizontal {
                messages.append("“\(config.exportDirectoryName)/\(config.horizontalDirectoryName)/” exists but “\(config.rawDirectoryName)/\(config.horizontalDirectoryName)/” is missing.")
            }
        } else {
            treeLines[treeLines.count - 2] = treeLines[treeLines.count - 2].replacingOccurrences(of: "├──", with: "├──")
        }

        if messages.isEmpty {
            return DroneProjectValidationResult(
                status: .valid,
                layoutMode: layoutMode,
                messages: ["Project layout looks good."],
                treeLines: treeLines
            )
        }

        return DroneProjectValidationResult(
            status: .validWithWarnings,
            layoutMode: layoutMode,
            messages: messages,
            treeLines: treeLines
        )
    }

    static func createMissingOrientationDirectories(
        projectDirectory: URL,
        config: DroneFinalizeConfig,
        layoutMode: DroneProjectLayoutMode
    ) throws {
        guard case let .oriented(needsVertical, needsHorizontal) = layoutMode else { return }
        let fileManager = FileManager.default
        let roots = [
            projectDirectory.appendingPathComponent(config.rawDirectoryName, isDirectory: true),
            projectDirectory.appendingPathComponent(config.exportDirectoryName, isDirectory: true),
        ]
        for root in roots {
            if needsVertical {
                try fileManager.createDirectory(
                    at: root.appendingPathComponent(config.verticalDirectoryName, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            if needsHorizontal {
                try fileManager.createDirectory(
                    at: root.appendingPathComponent(config.horizontalDirectoryName, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func invalid(messages: [String], treeLines: [String]) -> DroneProjectValidationResult {
        DroneProjectValidationResult(
            status: .invalid,
            layoutMode: nil,
            messages: messages,
            treeLines: treeLines
        )
    }

    private static func appendOrientationTree(
        to treeLines: inout [String],
        rawVertical: Bool,
        rawHorizontal: Bool,
        exportVertical: Bool,
        exportHorizontal: Bool,
        config: DroneFinalizeConfig
    ) {
        if rawVertical {
            treeLines[1] = treeLines[1].replacingOccurrences(of: "├──", with: "├──") + " (\(config.verticalDirectoryName)/)"
        }
        if exportVertical {
            treeLines[2] = treeLines[2].replacingOccurrences(of: "└──", with: "└──") + " (\(config.verticalDirectoryName)/)"
        }
        if rawHorizontal {
            treeLines[1] += rawVertical ? ", \(config.horizontalDirectoryName)/" : " (\(config.horizontalDirectoryName)/)"
        }
        if exportHorizontal {
            treeLines[2] += exportVertical ? ", \(config.horizontalDirectoryName)/" : " (\(config.horizontalDirectoryName)/)"
        }
    }
}
