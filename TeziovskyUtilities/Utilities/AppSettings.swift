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
    private static let organizeByYearEnabledKey = "organizeByYearEnabled"
    private static let droneCompressedSuffixKey = "droneCompressedSuffix"
    private static let droneRawDirectoryNameKey = "droneRawDirectoryName"
    private static let droneExportDirectoryNameKey = "droneExportDirectoryName"
    private static let droneVerticalDirectoryNameKey = "droneVerticalDirectoryName"
    private static let droneHorizontalDirectoryNameKey = "droneHorizontalDirectoryName"
    private static let droneHandBrakeCLIPathKey = "droneHandBrakeCLIPath"
    private static let droneResolveAppPathKey = "droneResolveAppPath"
    private static let droneHandBrakeOutputExtensionKey = "droneHandBrakeOutputExtension"
    private static let droneKeepRawAfterFinalizeKey = "droneKeepRawAfterFinalize"
    private static let dronePreserveOrientationOnFlattenKey = "dronePreserveOrientationOnFlatten"
    private static let droneLastHandBrakePresetKey = "droneLastHandBrakePreset"
    private static let fileDateRepairExtensionsKey = "fileDateRepairExtensions"

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

    static var organizeByYearEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: organizeByYearEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: organizeByYearEnabledKey) }
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

    static var droneVerticalDirectoryName: String {
        get {
            let value = UserDefaults.standard.string(forKey: droneVerticalDirectoryNameKey)
            return (value?.isEmpty == false) ? value! : DroneFinalizeConfig.default.verticalDirectoryName
        }
        set { UserDefaults.standard.set(newValue, forKey: droneVerticalDirectoryNameKey) }
    }

    static var droneHorizontalDirectoryName: String {
        get {
            let value = UserDefaults.standard.string(forKey: droneHorizontalDirectoryNameKey)
            return (value?.isEmpty == false) ? value! : DroneFinalizeConfig.default.horizontalDirectoryName
        }
        set { UserDefaults.standard.set(newValue, forKey: droneHorizontalDirectoryNameKey) }
    }

    static var droneHandBrakeCLIPath: String {
        get { UserDefaults.standard.string(forKey: droneHandBrakeCLIPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: droneHandBrakeCLIPathKey) }
    }

    static var droneResolveAppPath: String {
        get { UserDefaults.standard.string(forKey: droneResolveAppPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: droneResolveAppPathKey) }
    }

    static var droneHandBrakeOutputExtension: String {
        get {
            let value = UserDefaults.standard.string(forKey: droneHandBrakeOutputExtensionKey)
            return DroneFinalizeConfig.normalizeOutputExtension(value ?? "")
        }


        set {
            UserDefaults.standard.set(
                DroneFinalizeConfig.normalizeOutputExtension(newValue),
                forKey: droneHandBrakeOutputExtensionKey
            )
        }
    }

    static var droneKeepRawAfterFinalize: Bool {
        get {
            if UserDefaults.standard.object(forKey: droneKeepRawAfterFinalizeKey) == nil {
                return DroneFinalizeConfig.default.keepRawAfterFinalize
            }
            return UserDefaults.standard.bool(forKey: droneKeepRawAfterFinalizeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: droneKeepRawAfterFinalizeKey) }
    }

    static var dronePreserveOrientationOnFlatten: Bool {
        get {
            if UserDefaults.standard.object(forKey: dronePreserveOrientationOnFlattenKey) == nil {
                return DroneFinalizeConfig.default.preserveOrientationOnFlatten
            }
            return UserDefaults.standard.bool(forKey: dronePreserveOrientationOnFlattenKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: dronePreserveOrientationOnFlattenKey) }
    }

    static var droneLastHandBrakePreset: String {
        get { UserDefaults.standard.string(forKey: droneLastHandBrakePresetKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: droneLastHandBrakePresetKey) }
    }

    static var droneFinalizeConfig: DroneFinalizeConfig {
        DroneFinalizeConfig(
            compressedSuffix: droneCompressedSuffix,
            rawDirectoryName: droneRawDirectoryName,
            exportDirectoryName: droneExportDirectoryName,
            verticalDirectoryName: droneVerticalDirectoryName,
            horizontalDirectoryName: droneHorizontalDirectoryName,
            handBrakeCLIPath: droneHandBrakeCLIPath,
            resolveAppPath: droneResolveAppPath,
            handBrakeOutputExtension: droneHandBrakeOutputExtension,
            keepRawAfterFinalize: droneKeepRawAfterFinalize,
            preserveOrientationOnFlatten: dronePreserveOrientationOnFlatten
        )
    }

    // MARK: - File date repair

    static var fileDateRepairExtensions: String {
        get {
            UserDefaults.standard.string(forKey: fileDateRepairExtensionsKey)
                ?? FileDateRepairExtensions.defaults.joined(separator: ", ")
        }
        set {
            UserDefaults.standard.set(
                FileDateRepairExtensions.normalizedString(newValue),
                forKey: fileDateRepairExtensionsKey
            )
        }
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
