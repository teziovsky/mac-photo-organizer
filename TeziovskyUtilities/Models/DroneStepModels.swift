import Foundation

/// The ordered steps of the drone finalize wizard.
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
        case .merge: return "Step 1 — Merge metadata"
        case .cleanup: return "Step 2 — Delete originals & rename"
        case .flatten: return "Step 3 — Flatten project folder"
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
