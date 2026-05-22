import Foundation
import Photos

struct MediaItem: Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let isVideo: Bool
    let creationDate: Date?

    var asset: PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }
}
