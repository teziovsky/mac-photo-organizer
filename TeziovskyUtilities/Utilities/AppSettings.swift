import Foundation

enum AppSettings {
    private static let excludedSuffixKey = "excludedAlbumSuffix"
    private static let omittedFromOrganizeAlbumIDsKey = "omittedFromOrganizeAlbumIDs"
    private static let thumbnailDisplayModeKey = "thumbnailDisplayMode"
    private static let mediaGridColumnCountKey = "mediaGridColumnCount"
    static let mediaGridColumnCountMin = 3
    static let mediaGridColumnCountMax = 9
    private static let defaultMediaGridColumnCount = 6
    private static let exportDirectoryBookmarkKey = "exportDirectoryBookmark"
    private static let exportDirectoryPathKey = "exportDirectoryPath"
    private static let droneCompressedSuffixKey = "droneCompressedSuffix"
    private static let droneRawDirectoryNameKey = "droneRawDirectoryName"
    private static let droneExportDirectoryNameKey = "droneExportDirectoryName"

    static var mediaGridColumnCount: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: mediaGridColumnCountKey)
            let value = stored > 0 ? stored : defaultMediaGridColumnCount
            return min(max(value, mediaGridColumnCountMin), mediaGridColumnCountMax)
        }
        set {
            let clamped = min(max(newValue, mediaGridColumnCountMin), mediaGridColumnCountMax)
            UserDefaults.standard.set(clamped, forKey: mediaGridColumnCountKey)
        }
    }

    static var thumbnailDisplayMode: ThumbnailDisplayMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: thumbnailDisplayModeKey),
                  let mode = ThumbnailDisplayMode(rawValue: raw) else {
                return .square
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: thumbnailDisplayModeKey)
        }
    }

    static var excludedAlbumSuffix: String {
        get {
            let value = UserDefaults.standard.string(forKey: excludedSuffixKey)
            return value ?? "_zgrane"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: excludedSuffixKey)
        }
    }

    static var omittedFromOrganizeAlbumIDs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: omittedFromOrganizeAlbumIDsKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: omittedFromOrganizeAlbumIDsKey)
        }
    }

    static func isAlbumOmittedFromOrganize(albumID: String) -> Bool {
        omittedFromOrganizeAlbumIDs.contains(albumID)
    }

    static var exportDirectoryPath: String? {
        get { UserDefaults.standard.string(forKey: exportDirectoryPathKey) }
        set { UserDefaults.standard.set(newValue, forKey: exportDirectoryPathKey) }
    }

    // MARK: - Drone finalize

    static var droneCompressedSuffix: String {
        get {
            let value = UserDefaults.standard.string(forKey: droneCompressedSuffixKey)
            return (value?.isEmpty == false) ? value! : DroneFinalizeConfig.default.compressedSuffix
        }
        set { UserDefaults.standard.set(newValue, forKey: droneCompressedSuffixKey) }
    }

    static var droneRawDirectoryName: String {
        get {
            let value = UserDefaults.standard.string(forKey: droneRawDirectoryNameKey)
            return (value?.isEmpty == false) ? value! : DroneFinalizeConfig.default.rawDirectoryName
        }
        set { UserDefaults.standard.set(newValue, forKey: droneRawDirectoryNameKey) }
    }

    static var droneExportDirectoryName: String {
        get {
            let value = UserDefaults.standard.string(forKey: droneExportDirectoryNameKey)
            return (value?.isEmpty == false) ? value! : DroneFinalizeConfig.default.exportDirectoryName
        }
        set { UserDefaults.standard.set(newValue, forKey: droneExportDirectoryNameKey) }
    }

    static var droneFinalizeConfig: DroneFinalizeConfig {
        DroneFinalizeConfig(
            compressedSuffix: droneCompressedSuffix,
            rawDirectoryName: droneRawDirectoryName,
            exportDirectoryName: droneExportDirectoryName
        )
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
