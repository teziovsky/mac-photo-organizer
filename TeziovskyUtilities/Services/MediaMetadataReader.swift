import AVFoundation
import Foundation
import ImageIO

/// Reads displayable metadata from a media file (filesystem dates/size plus, where
/// available, container creation date, dimensions, and duration).
enum MediaMetadataReader {
    static func readDateEvidence(url: URL, isVideo: Bool) async throws -> [FileDateEvidence] {
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        var evidence: [FileDateEvidence] = []
        if let date = values.creationDate {
            evidence.append(FileDateEvidence(source: .filesystemCreation, date: date))
        }
        if let date = values.contentModificationDate {
            evidence.append(FileDateEvidence(source: .filesystemModification, date: date))
        }

        if isVideo {
            evidence.append(contentsOf: await readVideoDateEvidence(url: url))
            try Task.checkCancellation()
        } else {
            evidence.append(contentsOf: readImageDateEvidence(url: url))
        }
        return evidence
    }

    static func read(url: URL, isVideo: Bool) async -> MediaMetadataSnapshot {
        var snapshot = MediaMetadataSnapshot(fileName: url.lastPathComponent)

        if let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ]) {
            if let size = values.fileSize { snapshot.fileSizeBytes = Int64(size) }
            snapshot.creationDate = values.creationDate
            snapshot.modificationDate = values.contentModificationDate
        }

        if isVideo {
            await readVideoMetadata(url: url, into: &snapshot)
        } else {
            readImageMetadata(url: url, into: &snapshot)
        }
        return snapshot
    }

    private static func readVideoMetadata(url: URL, into snapshot: inout MediaMetadataSnapshot) async {
        let asset = AVURLAsset(url: url)

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite, seconds > 0 {
                snapshot.duration = formatDuration(seconds)
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first,
           let size = try? await track.load(.naturalSize) {
            snapshot.dimensions = "\(Int(abs(size.width))) × \(Int(abs(size.height)))"
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata where item.commonKey == .commonKeyCreationDate {
                if let date = try? await item.load(.dateValue) {
                    snapshot.containerCreationDate = date
                    break
                }
                if let string = try? await item.load(.stringValue),
                   let date = parseDateString(string) {
                    snapshot.containerCreationDate = date
                    break
                }
            }
        }
    }

    private static func readVideoDateEvidence(url: URL) async -> [FileDateEvidence] {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return [] }
        var dates: [Date] = []
        for item in metadata where item.commonKey == .commonKeyCreationDate {
            if let date = try? await item.load(.dateValue) {
                dates.append(date)
                continue
            }
            if let string = try? await item.load(.stringValue),
               let date = parseDateString(string) {
                dates.append(date)
            }
        }
        return dates
            .reduce(into: [Date]()) { uniqueDates, date in
                guard !uniqueDates.contains(where: {
                    abs($0.timeIntervalSince(date)) <= FileDateRepairPlanner.timestampTolerance
                }) else {
                    return
                }
                uniqueDates.append(date)
            }
            .map { FileDateEvidence(source: .containerCreation, date: $0) }
    }

    private static func readImageMetadata(url: URL, into snapshot: inout MediaMetadataSnapshot) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return
        }

        if let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            snapshot.dimensions = "\(width) × \(height)"
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = parseExifDate(original) {
            snapshot.containerCreationDate = date
        }
    }

    private static func readImageDateEvidence(url: URL) -> [FileDateEvidence] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return []
        }

        var evidence: [FileDateEvidence] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                index,
                nil
            ) as? [CFString: Any] else {
                continue
            }
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                appendDate(
                    exif[kCGImagePropertyExifDateTimeOriginal],
                    source: .exifOriginal,
                    to: &evidence
                )
                appendDate(
                    exif[kCGImagePropertyExifDateTimeDigitized],
                    source: .exifDigitized,
                    to: &evidence
                )
            }
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                appendDate(tiff[kCGImagePropertyTIFFDateTime], source: .tiffDateTime, to: &evidence)
            }
        }
        return evidence
    }

    private static func appendDate(
        _ rawValue: Any?,
        source: FileDateSource,
        to evidence: inout [FileDateEvidence]
    ) {
        guard let value = rawValue as? String, let date = parseExifDate(value) else { return }
        guard !evidence.contains(where: {
            $0.source == source &&
                abs($0.date.timeIntervalSince(date)) <= FileDateRepairPlanner.timestampTolerance
        }) else {
            return
        }
        evidence.append(FileDateEvidence(source: source, date: date))
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static func parseExifDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private static func parseDateString(_ value: String) -> Date? {
        if let date = parseExifDate(value) { return date }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: value)
    }
}
