import Foundation
import Photos

struct PhotoAlbum: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mediaCount: Int
    let photoCount: Int
    let videoCount: Int
    let collectionIdentifier: String

    var mediaSummary: String {
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) \(photoCount == 1 ? "photo" : "photos")")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) \(videoCount == 1 ? "video" : "videos")")
        }
        if parts.isEmpty {
            return "\(mediaCount) media"
        }
        return parts.joined(separator: ", ")
    }
}
