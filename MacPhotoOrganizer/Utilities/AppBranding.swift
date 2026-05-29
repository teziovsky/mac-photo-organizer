import Foundation

/// Single source of truth for user-facing branding strings.
///
/// To rename the app, update the canonical name in these spots (this file derives
/// the runtime name from Info.plist, so most UI updates automatically):
///   - `MacPhotoOrganizer/Info.plist` (`CFBundleDisplayName` / `CFBundleName`)
///   - `scripts/install-to-applications.sh` (`DEST_APP_NAME`)
///   - `README.md` and `package.json`
enum AppBranding {
    /// Hardcoded fallback used only when Info.plist is unavailable (e.g. SPM CLI builds).
    static let fallbackAppName = "Media Organizer"

    /// Canonical app name, read from Info.plist so the displayed name has one source.
    static let appName: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackAppName

    static let photosModeTitle = "Organize Photos"
    static let photosModeSubtitle = "Review iCloud Photos albums and export them to a folder."
    static let photosModeIcon = "photo.on.rectangle.angled"

    static let droneModeTitle = "Organize Drone Footage"
    static let droneModeSubtitle = "Finalize a graded project: merge metadata, drop the compressed suffix, and flatten into one folder."
    static let droneModeIcon = "airplane"
}
