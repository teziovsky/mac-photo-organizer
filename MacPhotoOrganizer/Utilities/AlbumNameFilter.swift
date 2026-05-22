import Foundation

enum AlbumNameFilter {
    static func shouldInclude(albumName: String, excludedSuffix: String) -> Bool {
        let trimmed = excludedSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return !albumName.hasSuffix(trimmed)
    }
}
