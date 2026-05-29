import Darwin
import Foundation
import ImageIO
import Photos

enum FileDatePreservation {
    /// Applies Photos / EXIF dates to every layer Finder uses for "Created" (filesystem birth time).
    static func apply(from asset: PHAsset, to url: URL) throws {
        let created = canonicalCreationDate(for: asset, fileURL: url)
        let modified = asset.modificationDate ?? created
        try applyFileDates(to: url, created: created, modified: modified)
    }

    static func canonicalCreationDate(for asset: PHAsset, fileURL: URL) -> Date {
        if let exifDate = readExifOriginalDate(from: fileURL) {
            return exifDate
        }
        return asset.creationDate ?? asset.modificationDate ?? Date()
    }

    /// Copies the source file's creation (birth) and modification dates onto the destination file.
    /// Used by the drone finalize step so a compressed file inherits its original's Finder dates.
    static func copyFileDates(from sourceURL: URL, to destinationURL: URL) throws {
        let values = try sourceURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let created = values.creationDate ?? values.contentModificationDate ?? Date()
        let modified = values.contentModificationDate ?? created
        try applyFileDates(to: destinationURL, created: created, modified: modified)
    }

    private static func readExifOriginalDate(from url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = parseExifDate(original) {
            return date
        }

        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let tiffDate = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = parseExifDate(tiffDate) {
            return date
        }

        return nil
    }

    private static func parseExifDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: value)
    }

    private static func applyFileDates(to url: URL, created: Date, modified: Date) throws {
        try setAPFSBirthAndModificationTimes(url: url, created: created, modified: modified)

        var resourceValues = URLResourceValues()
        resourceValues.creationDate = created
        resourceValues.contentModificationDate = modified
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)

        try FileManager.default.setAttributes(
            [
                .creationDate: created,
                .modificationDate: modified,
            ],
            ofItemAtPath: url.path
        )
    }

    /// Sets APFS birth time (Finder "Date Created"). Must run after any file replace/move.
    private static func setAPFSBirthAndModificationTimes(
        url: URL,
        created: Date,
        modified: Date
    ) throws {
        var crtime = makeTimespec(from: created)
        var modtime = makeTimespec(from: modified)
        var attributeList = attrlist()
        attributeList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributeList.commonattr = attrgroup_t(UInt32(ATTR_CMN_CRTIME | ATTR_CMN_MODTIME))

        try url.path.withCString { path in
            let status = withUnsafeMutablePointer(to: &attributeList) { listPointer in
                withUnsafeMutablePointer(to: &crtime) { createdPointer in
                    withUnsafeMutablePointer(to: &modtime) { modifiedPointer in
                        var buffer = (createdPointer.pointee, modifiedPointer.pointee)
                        return withUnsafeMutablePointer(to: &buffer) { bufferPointer in
                            setattrlist(
                                path,
                                UnsafeMutableRawPointer(listPointer).assumingMemoryBound(to: attrlist.self),
                                UnsafeMutableRawPointer(bufferPointer),
                                MemoryLayout<timespec>.size * 2,
                                0
                            )
                        }
                    }
                }
            }
            if status != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
            }
        }
    }

    private static func makeTimespec(from date: Date) -> timespec {
        let seconds = date.timeIntervalSince1970
        var spec = timespec()
        spec.tv_sec = __darwin_time_t(seconds.rounded(.down))
        let fraction = seconds - Double(spec.tv_sec)
        spec.tv_nsec = Int((fraction * 1_000_000_000).rounded())
        return spec
    }
}
