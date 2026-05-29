import Foundation

enum MediaSummary {
    static func text(photoCount: Int, videoCount: Int, mediaCount: Int) -> String {
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) \(photoCount == 1 ? "photo" : "photos")")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) \(videoCount == 1 ? "video" : "videos")")
        }
        if parts.isEmpty {
            return "\(mediaCount) \(mediaCount == 1 ? "item" : "items")"
        }
        return parts.joined(separator: ", ")
    }

    static func text(for items: [MediaItem]) -> String {
        let videoCount = items.filter(\.isVideo).count
        let photoCount = items.count - videoCount
        return text(photoCount: photoCount, videoCount: videoCount, mediaCount: items.count)
    }
}
