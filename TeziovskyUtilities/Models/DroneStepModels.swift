import Foundation

/// Top-level phases of the guided drone workflow.
enum DroneWorkflowPhase: Int, CaseIterable, Sendable {
    case validateLayout = 0
    case waitForResolve
    case scanExport
    case pickPreset
    case compress
    case finalize
    case done

    var stepNumber: Int { rawValue + 1 }

    var shortTitle: String {
        switch self {
        case .validateLayout: return "Layout"
        case .waitForResolve: return "Resolve"
        case .scanExport: return "Scan"
        case .pickPreset: return "Preset"
        case .compress: return "Compress"
        case .finalize: return "Finalize"
        case .done: return "Done"
        }
    }

    var title: String {
        switch self {
        case .validateLayout: return "Step 1 — Validate project layout"
        case .waitForResolve: return "Step 2 — Edit in DaVinci Resolve"
        case .scanExport: return "Step 3 — Scan exports"
        case .pickPreset: return "Step 4 — Choose HandBrake preset"
        case .compress: return "Step 5 — Compress exports"
        case .finalize: return "Step 6 — Finalize delivery files"
        case .done: return "Finished"
        }
    }

    var systemImage: String {
        switch self {
        case .validateLayout: return "folder.badge.checkmark"
        case .waitForResolve: return "film.stack"
        case .scanExport: return "doc.text.magnifyingglass"
        case .pickPreset: return "slider.horizontal.3"
        case .compress: return "arrow.down.circle"
        case .finalize: return "wand.and.stars"
        case .done: return "checkmark.seal"
        }
    }
}

/// The ordered steps of the drone finalize sub-wizard.
enum DroneFinalizeStep: Int, CaseIterable, Sendable {
    case merge = 0
    case cleanup
    case flatten
    case done

    var stepNumber: Int { rawValue + 1 }

    var shortTitle: String {
        switch self {
        case .merge: return "Merge metadata"
        case .cleanup: return "Delete & rename"
        case .flatten: return "Flatten"
        case .done: return "Done"
        }
    }

    var title: String {
        switch self {
        case .merge: return "Merge metadata"
        case .cleanup: return "Delete originals & rename"
        case .flatten: return "Flatten project folder"
        case .done: return "Finished"
        }
    }

    var systemImage: String {
        switch self {
        case .merge: return "wand.and.stars"
        case .cleanup: return "trash.and.text.magnifyingglass"
        case .flatten: return "square.stack.3d.up"
        case .done: return "checkmark.seal"
        }
    }

    var actionTitle: String {
        switch self {
        case .merge: return "Merge"
        case .cleanup: return "Delete & Rename"
        case .flatten: return "Flatten & Finish"
        case .done: return "Done"
        }
    }
}

/// A read-only snapshot of a file's metadata for display in the merge step.
struct MediaMetadataSnapshot: Sendable, Equatable {
    var fileName: String
    var fileSizeBytes: Int64?
    var creationDate: Date?
    var modificationDate: Date?
    var containerCreationDate: Date?
    var dimensions: String?
    var duration: String?
}

/// A matched original/compressed pair plus its loaded metadata (for the merge step UI).
struct DronePairMetadata: Identifiable, Sendable {
    let id: String
    let sourceName: String
    let compressedName: String
    let finalName: String
    let isVideo: Bool
    var original: MediaMetadataSnapshot?
    var compressed: MediaMetadataSnapshot?
}
