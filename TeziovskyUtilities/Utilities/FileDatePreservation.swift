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

    /// Updates Finder's "Date Created" without changing the file's content modification date.
    static func applyCreationDate(_ created: Date, to url: URL) throws {
        let originalModified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        var didApply = false
        var lastError: Error?

        do {
            try setAPFSBirthTime(url: url, created: created)
            didApply = true
        } catch {
            lastError = error
        }

        do {
            var values = URLResourceValues()
            values.creationDate = created
            var mutableURL = url
            try mutableURL.setResourceValues(values)
            didApply = true
        } catch {
            lastError = error
        }

        do {
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
            didApply = true
        } catch {
            lastError = error
        }

        if let originalModified {
            var didRestore = false
            var restoreError: Error?
            do {
                var values = URLResourceValues()
                values.contentModificationDate = originalModified
                var mutableURL = url
                try mutableURL.setResourceValues(values)
                didRestore = true
            } catch {
                restoreError = error
            }
            do {
                try FileManager.default.setAttributes(
                    [.modificationDate: originalModified],
                    ofItemAtPath: url.path
                )
                didRestore = true
            } catch {
                restoreError = error
            }
            if !didRestore {
                throw restoreError ?? POSIXError(.EINVAL)
            }
        }

        if !didApply {
            throw lastError ?? POSIXError(.EINVAL)
        }
    }

    static func applyCreationDate(
        _ created: Date,
        preservingModificationDate modified: Date,
        to url: URL
    ) throws {
        try applyFileDates(to: url, created: created, modified: modified)
    }

    /// Rewrites every existing EXIF/TIFF creation field without adding fields the file
    /// did not already contain. All image frames are copied to the replacement file.
    static func synchronizeImageCreationDates(in url: URL, to date: Date) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let destinationType = CGImageSourceGetType(source) else {
            throw CocoaError(
                .fileReadCorruptFile,
                userInfo: [NSLocalizedDescriptionKey: "The image metadata could not be read."]
            )
        }

        let formattedDate = formatExifDate(date)
        let imageCount = CGImageSourceGetCount(source)
        var propertiesByIndex: [[CFString: Any]] = []
        var didFindCreationDate = false
        for index in 0..<imageCount {
            guard var properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                index,
                nil
            ) as? [CFString: Any] else {
                throw CocoaError(
                    .fileReadCorruptFile,
                    userInfo: [NSLocalizedDescriptionKey: "The image metadata could not be read."]
                )
            }
            didFindCreationDate = synchronizeImageProperties(
                &properties,
                formattedDate: formattedDate
            ) || didFindCreationDate
            propertiesByIndex.append(properties)
        }
        guard didFindCreationDate else { return }

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".image-metadata-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            destinationType,
            imageCount,
            nil
        ) else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "A replacement image could not be created."]
            )
        }

        for (index, properties) in propertiesByIndex.enumerated() {
            CGImageDestinationAddImageFromSource(
                destination,
                source,
                index,
                properties as CFDictionary
            )
        }
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "The synchronized image metadata could not be saved."]
            )
        }

        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tempURL, to: url)
    }

    /// Restores a previously captured filesystem date pair after an unsuccessful repair.
    static func restoreFileDates(created: Date, modified: Date, to url: URL) throws {
        try applyFileDates(to: url, created: created, modified: modified)
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

    private static func formatExifDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func synchronizeImageProperties(
        _ properties: inout [CFString: Any],
        formattedDate: String
    ) -> Bool {
        var didUpdate = false
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if exif[kCGImagePropertyExifDateTimeOriginal] != nil {
                exif[kCGImagePropertyExifDateTimeOriginal] = formattedDate
                didUpdate = true
            }
            if exif[kCGImagePropertyExifDateTimeDigitized] != nil {
                exif[kCGImagePropertyExifDateTimeDigitized] = formattedDate
                didUpdate = true
            }
            properties[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           tiff[kCGImagePropertyTIFFDateTime] != nil {
            tiff[kCGImagePropertyTIFFDateTime] = formattedDate
            properties[kCGImagePropertyTIFFDictionary] = tiff
            didUpdate = true
        }
        return didUpdate
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
                .modificationDate: modified
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

    private static func setAPFSBirthTime(url: URL, created: Date) throws {
        var crtime = makeTimespec(from: created)
        var attributeList = attrlist()
        attributeList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributeList.commonattr = attrgroup_t(UInt32(ATTR_CMN_CRTIME))

        try url.path.withCString { path in
            let status = withUnsafeMutablePointer(to: &attributeList) { listPointer in
                withUnsafeMutablePointer(to: &crtime) { createdPointer in
                    setattrlist(
                        path,
                        UnsafeMutableRawPointer(listPointer).assumingMemoryBound(to: attrlist.self),
                        UnsafeMutableRawPointer(createdPointer),
                        MemoryLayout<timespec>.size,
                        0
                    )
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
