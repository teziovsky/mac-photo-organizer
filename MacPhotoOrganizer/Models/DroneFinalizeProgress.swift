import Foundation

/// Progress for the drone finalize run. Mirrors the shape of `OrganizeProgress`.
struct DroneFinalizeProgress: Sendable {
    let current: Int
    let total: Int
    let detail: String
    let processedCount: Int
    let movedCount: Int
    let failedCount: Int
    let isComplete: Bool
    let wasCancelled: Bool

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    static func initial(total: Int) -> DroneFinalizeProgress {
        DroneFinalizeProgress(
            current: 0,
            total: total,
            detail: "",
            processedCount: 0,
            movedCount: 0,
            failedCount: 0,
            isComplete: false,
            wasCancelled: false
        )
    }
}
