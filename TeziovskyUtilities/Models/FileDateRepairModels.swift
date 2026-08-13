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
    let proposedDate: Date
    let proposedSource: FileDateSource
    let evidence: [FileDateEvidence]

    /// Newest timestamp that still disagrees with the proposed date, used in the repair list.
    var newestDisagreeingDate: Date {
        evidence
            .map(\.date)
            .filter { abs($0.timeIntervalSince(proposedDate)) > FileDateRepairPlanner.timestampTolerance }
            .max() ?? currentCreationDate
    }
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

        guard evidence.contains(where: {
            abs($0.date.timeIntervalSince(oldest.date)) > timestampTolerance
        }) else {
            return nil
        }

        return FileDateRepairItem(
            relativePath: relativePath,
            fileURL: fileURL,
            currentCreationDate: creation,
            proposedDate: oldest.date,
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

    /// True when at least one embedded creation date disagrees with the target.
    static func embeddedCreationDatesNeedSync(
        _ evidence: [FileDateEvidence],
        target: Date,
        tolerance: TimeInterval = timestampTolerance
    ) -> Bool {
        evidence.contains {
            $0.source.isEmbeddedCreationDate &&
                abs($0.date.timeIntervalSince(target)) > tolerance
        }
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

enum FileDateRepairVerification {
    enum Failure: Equatable {
        case missingCreationDate
        case creationDateMismatch
        case missingModificationDate
        case modificationDateMismatch
        case embeddedDateMismatch(FileDateSource)
        case embeddedDatesMissing

        var message: String {
            switch self {
            case .missingCreationDate:
                return "The filesystem creation date could not be verified after writing."
            case .creationDateMismatch:
                return "The filesystem creation date did not match the target after writing."
            case .missingModificationDate:
                return "The filesystem modification date could not be verified after writing."
            case .modificationDateMismatch:
                return "The filesystem modification date did not match the target after writing."
            case .embeddedDateMismatch(let source):
                return "\(source.label) did not match the target after writing."
            case .embeddedDatesMissing:
                return "Embedded creation dates were lost while writing metadata."
            }
        }
    }

    /// Confirms filesystem dates and any remaining embedded creation dates match the target.
    /// Sources that ImageIO drops on rewrite are allowed to disappear, but every remaining
    /// embedded creation date must match and at least one expected source must survive.
    static func validate(
        _ evidence: [FileDateEvidence],
        expectedEmbeddedSources: Set<FileDateSource>,
        target: Date,
        tolerance: TimeInterval = FileDateRepairPlanner.timestampTolerance
    ) -> Failure? {
        guard let created = evidence.first(where: { $0.source == .filesystemCreation })?.date else {
            return .missingCreationDate
        }
        guard abs(created.timeIntervalSince(target)) <= tolerance else {
            return .creationDateMismatch
        }
        guard let modified = evidence.first(where: { $0.source == .filesystemModification })?.date else {
            return .missingModificationDate
        }
        guard abs(modified.timeIntervalSince(target)) <= tolerance else {
            return .modificationDateMismatch
        }

        let embedded = evidence.filter(\.source.isEmbeddedCreationDate)
        for item in embedded {
            guard abs(item.date.timeIntervalSince(target)) <= tolerance else {
                return .embeddedDateMismatch(item.source)
            }
        }
        if !expectedEmbeddedSources.isEmpty, embedded.isEmpty {
            return .embeddedDatesMissing
        }
        return nil
    }
}
