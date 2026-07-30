import Foundation

enum FileDateSource: String, CaseIterable, Sendable {
    case filesystemCreation
    case filesystemModification
    case exifOriginal
    case exifDigitized
    case tiffDateTime
    case containerCreation

    var label: String {
        switch self {
        case .filesystemCreation: return "Filesystem Created"
        case .filesystemModification: return "Filesystem Modified"
        case .exifOriginal: return "EXIF Date Taken"
        case .exifDigitized: return "EXIF Digitized"
        case .tiffDateTime: return "TIFF Date/Time"
        case .containerCreation: return "Media Container Created"
        }
    }

    var isCreationDate: Bool {
        self != .filesystemModification
    }

    var isEmbeddedCreationDate: Bool {
        switch self {
        case .exifOriginal, .exifDigitized, .tiffDateTime, .containerCreation:
            return true
        case .filesystemCreation, .filesystemModification:
            return false
        }
    }
}

struct FileDateEvidence: Identifiable, Sendable, Equatable {
    var id: String { "\(source.rawValue)-\(date.timeIntervalSinceReferenceDate)" }
    let source: FileDateSource
    let date: Date
}

struct FileDateRepairItem: Identifiable, Sendable, Equatable {
    var id: String { relativePath }
    let relativePath: String
    let fileURL: URL
    let currentCreationDate: Date
    let proposedCreationDate: Date
    let proposedSource: FileDateSource
    let evidence: [FileDateEvidence]
}

struct FileDateRepairFailure: Identifiable, Sendable, Equatable {
    let id = UUID()
    let relativePath: String
    let message: String
}

struct FileDateRepairProgress: Sendable, Equatable {
    var processed = 0
    var total = 0
    var currentPath = ""

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(processed) / Double(total)
    }
}

enum FileDateRepairPlanner {
    static let timestampTolerance: TimeInterval = 1

    static func makeItem(
        fileURL: URL,
        relativePath: String,
        evidence: [FileDateEvidence],
        now: Date = Date()
    ) -> FileDateRepairItem? {
        guard let creation = evidence.first(where: { $0.source == .filesystemCreation })?.date else {
            return nil
        }

        let validCandidates = evidence.filter { isPlausible($0.date, now: now) }
        guard let oldest = validCandidates.min(by: { $0.date < $1.date }) else {
            return nil
        }

        let creationDates = evidence.filter(\.source.isCreationDate)
        guard creationDates.contains(where: {
            abs($0.date.timeIntervalSince(oldest.date)) > timestampTolerance
        }) else {
            return nil
        }

        return FileDateRepairItem(
            relativePath: relativePath,
            fileURL: fileURL,
            currentCreationDate: creation,
            proposedCreationDate: oldest.date,
            proposedSource: oldest.source,
            evidence: evidence.sorted(by: evidenceSort)
        )
    }

    private static func isPlausible(_ date: Date, now: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let minimum = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
        return date >= minimum && date <= now.addingTimeInterval(24 * 60 * 60)
    }

    private static func evidenceSort(_ lhs: FileDateEvidence, _ rhs: FileDateEvidence) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.source.rawValue < rhs.source.rawValue
    }
}

enum FileDateRepairExtensions {
    static let defaults = [
        "3gp", "avi", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "m4v",
        "mov", "mp4", "mpeg", "mpg", "png", "tif", "tiff", "webp"
    ]

    static func parse(_ value: String) -> Set<String> {
        Set(
            value
                .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
                .map(normalize)
                .filter { !$0.isEmpty }
        )
    }

    static func normalizedString(_ value: String) -> String {
        parse(value).sorted().joined(separator: ", ")
    }

    static func supports(_ url: URL, extensions: Set<String>) -> Bool {
        extensions.contains(normalize(url.pathExtension))
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
    }
}

enum FileDateRepairChunker {
    static func next(
        from items: [FileDateRepairItem],
        attemptedIDs: Set<String>,
        size: Int
    ) -> [FileDateRepairItem] {
        guard size > 0 else { return [] }
        return Array(items.lazy.filter { !attemptedIDs.contains($0.id) }.prefix(size))
    }
}
