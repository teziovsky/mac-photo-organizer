import Foundation

/// Single source of truth for user-facing branding strings.
///
/// To rename the app, update the canonical name in these spots (this file derives
/// the runtime name from Info.plist, so most UI updates automatically):
///   - `TeziovskyUtilities/Info.plist` (`CFBundleDisplayName` / `CFBundleName`)
///   - `scripts/install-to-applications.sh` (`DEST_APP_NAME`)
///   - `README.md` and `package.json`
enum AppBranding {
    /// Hardcoded fallback used only when Info.plist is unavailable (e.g. SPM CLI builds).
    static let fallbackAppName = "Teziovsky Utilities"

    /// Canonical app name, read from Info.plist so the displayed name has one source.
    static let appName: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackAppName

    static let photosModeTitle = "Export iCloud Photos"
    static let photosModeSubtitle = "Review iCloud Photos albums and export originals to a folder."
    static let photosModeIcon = "icloud.and.arrow.down"

    static let droneModeTitle = "Organize Drone Footage"
    static let droneModeSubtitle = "Validate project, compress exports, finalize delivery files."
    static let droneModeIcon = "airplane"

    static let localPhotosModeTitle = "Organize Local Photos"
    static let localPhotosModeSubtitle = "Convert legacy media, repair dates, and organize files into year folders."
    static let localPhotosModeIcon = "folder.badge.gearshape"
}
