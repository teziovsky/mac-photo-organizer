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
        MediaSummary.text(photoCount: photoCount, videoCount: videoCount, mediaCount: mediaCount)
    }
}
