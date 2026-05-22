import Foundation

enum SafeFilename {
    /// Returns a single path segment safe for appending to an export or temp directory.
    static func sanitize(_ raw: String, fallback: String = "untitled") -> String {
        var name = (raw as NSString).lastPathComponent
        if name.isEmpty || name == "." || name == ".." {
            name = fallback
        }
        name = name.replacingOccurrences(of: "/", with: "_")
        name = name.replacingOccurrences(of: "\u{0000}", with: "")
        if name.isEmpty {
            name = fallback
        }
        return name
    }

    /// Builds a file URL under `directory` and verifies the resolved path stays inside it.
    static func fileURL(in directory: URL, filename raw: String, fallback: String = "untitled") -> URL? {
        let name = sanitize(raw, fallback: fallback)
        let destination = directory.appendingPathComponent(name)
        return isContained(destination, in: directory) ? destination : nil
    }

    static func isContained(_ fileURL: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }
}
