import Foundation

struct OrganizeProgress: Sendable {
    let current: Int
    let total: Int
    let filename: String
    let failedCount: Int
    let skippedCount: Int
    let isComplete: Bool
    let wasCancelled: Bool

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
}

struct OrganizeFailure: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let message: String
}
