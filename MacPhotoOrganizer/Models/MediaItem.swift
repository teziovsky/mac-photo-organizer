import Foundation

struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let isVideo: Bool
    let creationDate: Date?
}
