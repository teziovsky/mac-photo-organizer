import Foundation

/// Pairs security-scoped bookmark access for the export directory.
final class ExportDirectoryAccess {
    private var accessedURL: URL?

    func beginAccess() -> URL? {
        endAccess()
        guard let url = AppSettings.resolveExportDirectory() else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        accessedURL = url
        return url
    }

    func endAccess() {
        if let url = accessedURL {
            url.stopAccessingSecurityScopedResource()
            accessedURL = nil
        }
    }

    deinit {
        endAccess()
    }
}
