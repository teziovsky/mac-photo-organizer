import Foundation

enum AppSettings {
    private static let excludedSuffixKey = "excludedAlbumSuffix"
    private static let exportDirectoryBookmarkKey = "exportDirectoryBookmark"
    private static let exportDirectoryPathKey = "exportDirectoryPath"

    static var excludedAlbumSuffix: String {
        get {
            let value = UserDefaults.standard.string(forKey: excludedSuffixKey)
            return value ?? "_zgrane"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: excludedSuffixKey)
        }
    }

    static var exportDirectoryPath: String? {
        get { UserDefaults.standard.string(forKey: exportDirectoryPathKey) }
        set { UserDefaults.standard.set(newValue, forKey: exportDirectoryPathKey) }
    }

    static var exportDirectoryURL: URL? {
        guard let path = exportDirectoryPath else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setExportDirectory(_ url: URL) {
        exportDirectoryPath = url.path
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: exportDirectoryBookmarkKey)
        }
    }

    static func resolveExportDirectory() -> URL? {
        if let url = exportDirectoryURL, FileManager.default.fileExists(atPath: url.path) {
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        guard let data = UserDefaults.standard.data(forKey: exportDirectoryBookmarkKey) else {
            return exportDirectoryURL
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return exportDirectoryURL
        }
        _ = url.startAccessingSecurityScopedResource()
        exportDirectoryPath = url.path
        return url
    }
}
