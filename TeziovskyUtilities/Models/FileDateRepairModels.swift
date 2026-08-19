import Darwin
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

enum LocalVideoOutputContainer: String, CaseIterable, Sendable {
    case mp4
    case mov

    var label: String {
        switch self {
        case .mp4: return "MP4 — widest compatibility"
        case .mov: return "QuickTime MOV"
        }
    }

    var fileExtension: String { rawValue }
}

enum LocalVideoCodec: String, CaseIterable, Sendable {
    case h264
    case hevc

    var label: String {
        switch self {
        case .h264: return "H.264 + AAC — widest compatibility"
        case .hevc: return "HEVC + AAC — smaller files"
        }
    }
}

struct LocalMediaConversionConfig: Sendable, Equatable {
    let convertHEIC: Bool
    let convertLegacyVideos: Bool
    let keepOriginals: Bool
    let videoOutputContainer: LocalVideoOutputContainer
    let videoCodec: LocalVideoCodec

    init(
        convertHEIC: Bool = true,
        convertLegacyVideos: Bool = true,
        keepOriginals: Bool,
        videoOutputContainer: LocalVideoOutputContainer,
        videoCodec: LocalVideoCodec = .h264
    ) {
        self.convertHEIC = convertHEIC
        self.convertLegacyVideos = convertLegacyVideos
        self.keepOriginals = keepOriginals
        self.videoOutputContainer = videoOutputContainer
        self.videoCodec = videoCodec
    }

    static let `default` = LocalMediaConversionConfig(
        keepOriginals: true,
        videoOutputContainer: .mp4,
        videoCodec: .h264
    )
}

enum LocalMediaConversionKind: Sendable, Equatable {
    case heicToJPEG
    case legacyVideo(LocalVideoOutputContainer, LocalVideoCodec)

    var label: String {
        switch self {
        case .heicToJPEG: return "HEIC → highest-quality JPEG"
        case .legacyVideo(let container, let codec):
            return "Legacy video → \(container.fileExtension.uppercased()) · \(codec.label)"
        }
    }
}

struct LocalMediaConversionItem: Identifiable, Sendable, Equatable {
    var id: String { sourceRelativePath }
    let sourceURL: URL
    let sourceRelativePath: String
    let destinationURL: URL
    let destinationRelativePath: String
    let kind: LocalMediaConversionKind
    let keepOriginal: Bool
    let destinationWasRenamed: Bool
}

struct LocalMediaConversionSummary: Sendable, Equatable {
    var converted = 0
    var failed = 0
    var total = 0
    var wasCancelled = false
}

struct LocalMediaOrganizationItem: Identifiable, Sendable, Equatable {
    var id: String { sourceRelativePath }
    let sourceURL: URL
    let sourceRelativePath: String
    let destinationURL: URL
    let destinationRelativePath: String
    let proposedDate: Date
    let proposedSource: FileDateSource
    let isVideo: Bool
    let destinationWasRenamed: Bool
}

struct LocalMediaOrganizationSummary: Sendable, Equatable {
    var moved = 0
    var skipped = 0
    var failed = 0
    var total = 0
    var wasCancelled = false
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

        guard let oldest = oldestPlausibleEvidence(in: evidence, now: now) else {
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

    static func oldestPlausibleEvidence(
        in evidence: [FileDateEvidence],
        now: Date = Date()
    ) -> FileDateEvidence? {
        evidence
            .filter { isPlausible($0.date, now: now) }
            .min { $0.date < $1.date }
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

enum LocalMediaOrganizationPlanner {
    static let videoDirectoryName = "_Filmy"

    static func makeCandidate(
        fileURL: URL,
        relativePath: String,
        rootDirectory: URL,
        evidence: [FileDateEvidence],
        isVideo: Bool,
        now: Date = Date()
    ) -> LocalMediaOrganizationItem? {
        guard let oldest = FileDateRepairPlanner.oldestPlausibleEvidence(in: evidence, now: now) else {
            return nil
        }

        let year = yearString(for: oldest.date)
        let parent = fileURL.deletingLastPathComponent()
        let anchor: URL
        var preservedDirectories: [String] = []
        var prependVideoDirectory = isVideo

        if let currentYearDirectory = nearestYearDirectory(startingAt: parent) {
            preservedDirectories = relativeDirectoryComponents(
                from: currentYearDirectory,
                to: parent
            )
            let isInVideoDirectory = preservedDirectories.contains(videoDirectoryName)
            if currentYearDirectory.lastPathComponent == year {
                if !isVideo, !isInVideoDirectory {
                    return nil
                }
                if isVideo, isInVideoDirectory {
                    return nil
                }
            }
            if isVideo {
                prependVideoDirectory = false
                if !isInVideoDirectory {
                    preservedDirectories.append(videoDirectoryName)
                }
            } else {
                preservedDirectories.removeAll { $0 == videoDirectoryName }
            }
            anchor = currentYearDirectory.deletingLastPathComponent()
        } else {
            anchor = parent
        }

        var destinationDirectory = anchor.appendingPathComponent(year, isDirectory: true)
        if prependVideoDirectory {
            destinationDirectory.appendPathComponent(videoDirectoryName, isDirectory: true)
        }
        for component in preservedDirectories {
            destinationDirectory.appendPathComponent(component, isDirectory: true)
        }
        let destination = destinationDirectory.appendingPathComponent(fileURL.lastPathComponent)
        guard destination.standardizedFileURL != fileURL.standardizedFileURL,
              isWithinRoot(destination, rootDirectory: rootDirectory) else {
            return nil
        }

        return LocalMediaOrganizationItem(
            sourceURL: fileURL,
            sourceRelativePath: relativePath,
            destinationURL: destination,
            destinationRelativePath: makeRelativePath(for: destination, root: rootDirectory),
            proposedDate: oldest.date,
            proposedSource: oldest.source,
            isVideo: isVideo,
            destinationWasRenamed: false
        )
    }

    static func resolveCollisions(
        _ candidates: [LocalMediaOrganizationItem],
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) -> [LocalMediaOrganizationItem] {
        var reservedPaths = Set<String>()
        return candidates
            .sorted {
                $0.sourceRelativePath.localizedStandardCompare($1.sourceRelativePath) == .orderedAscending
            }
            .map { item in
                let destination = uniqueDestination(
                    preferred: item.destinationURL,
                    reservedPaths: &reservedPaths,
                    fileManager: fileManager
                )
                return LocalMediaOrganizationItem(
                    sourceURL: item.sourceURL,
                    sourceRelativePath: item.sourceRelativePath,
                    destinationURL: destination,
                    destinationRelativePath: makeRelativePath(for: destination, root: rootDirectory),
                    proposedDate: item.proposedDate,
                    proposedSource: item.proposedSource,
                    isVideo: item.isVideo,
                    destinationWasRenamed: destination.lastPathComponent != item.destinationURL.lastPathComponent
                )
            }
    }

    private static func uniqueDestination(
        preferred: URL,
        reservedPaths: inout Set<String>,
        fileManager: FileManager
    ) -> URL {
        var candidate = preferred
        let base = preferred.deletingPathExtension().lastPathComponent
        let fileExtension = preferred.pathExtension
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path)
            || reservedPaths.contains(candidate.standardizedFileURL.path) {
            let filename = fileExtension.isEmpty
                ? "\(base) (\(counter))"
                : "\(base) (\(counter)).\(fileExtension)"
            candidate = preferred.deletingLastPathComponent().appendingPathComponent(filename)
            counter += 1
        }
        reservedPaths.insert(candidate.standardizedFileURL.path)
        return candidate
    }

    private static func yearString(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return String(calendar.component(.year, from: date))
    }

    private static func isYearDirectory(_ name: String) -> Bool {
        name.count == 4 && name.allSatisfy(\.isNumber)
    }

    private static func nearestYearDirectory(startingAt directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while candidate.path != "/" {
            if isYearDirectory(candidate.lastPathComponent) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
        return nil
    }

    private static func relativeDirectoryComponents(from ancestor: URL, to descendant: URL) -> [String] {
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        let descendantComponents = descendant.standardizedFileURL.pathComponents
        guard descendantComponents.starts(with: ancestorComponents) else { return [] }
        return Array(descendantComponents.dropFirst(ancestorComponents.count))
    }

    private static func isWithinRoot(_ url: URL, rootDirectory: URL) -> Bool {
        let rootPath = canonicalPath(for: rootDirectory)
        let path = canonicalPath(for: url)
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func makeRelativePath(for url: URL, root: URL) -> String {
        let rootPath = canonicalPath(for: root)
        let path = canonicalPath(for: url)
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func canonicalPath(for url: URL, fileManager: FileManager = .default) -> String {
        var existingURL = url.standardizedFileURL
        var missingComponents: [String] = []
        while !fileManager.fileExists(atPath: existingURL.path) {
            let parent = existingURL.deletingLastPathComponent()
            guard parent.path != existingURL.path else { break }
            missingComponents.insert(existingURL.lastPathComponent, at: 0)
            existingURL = parent
        }

        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let didResolve = existingURL.path.withCString { path in
            buffer.withUnsafeMutableBufferPointer { pointer in
                realpath(path, pointer.baseAddress) != nil
            }
        }
        let existingPath = didResolve ? String(cString: buffer) : existingURL.path
        let completePath = missingComponents.reduce(URL(fileURLWithPath: existingPath)) {
            $0.appendingPathComponent($1)
        }.standardizedFileURL.path
        return normalizePrivateSystemAlias(completePath)
    }

    private static func normalizePrivateSystemAlias(_ path: String) -> String {
        for alias in ["/var", "/tmp", "/etc"] {
            let privateAlias = "/private\(alias)"
            if path == privateAlias || path.hasPrefix(privateAlias + "/") {
                return String(path.dropFirst("/private".count))
            }
        }
        return path
    }
}

enum FileDateRepairExtensions {
    static let defaults = [
        "3gp", "avi", "bmp", "flv", "gif", "heic", "heif", "jpeg", "jpg", "m2ts",
        "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "mts", "png", "qt", "tif", "tiff",
        "vob", "webp", "wmv"
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
