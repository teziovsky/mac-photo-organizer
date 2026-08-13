import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import TeziovskyUtilities

final class FileDateRepairPlannerTests: XCTestCase {
    func testChoosesOldestValidNonCreationDateAndReportsSource() {
        let created = date(2024)
        let modified = date(2015)
        let exif = date(2005)
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: created),
                FileDateEvidence(source: .filesystemModification, date: modified),
                FileDateEvidence(source: .exifOriginal, date: exif)
            ],
            now: date(2026)
        )

        XCTAssertEqual(item?.proposedDate, exif)
        XCTAssertEqual(item?.proposedSource, .exifOriginal)
        XCTAssertEqual(item?.currentCreationDate, created)
        XCTAssertEqual(item?.newestDisagreeingDate, created)
    }

    func testDoesNotProposeDateWithinTolerance() {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let modified = created.addingTimeInterval(-0.5)
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: created),
                FileDateEvidence(source: .filesystemModification, date: modified)
            ],
            now: date(2026)
        )

        XCTAssertNil(item)
    }

    func testChoosesOldestOfAllCreationFields() {
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: date(2024)),
                FileDateEvidence(source: .exifOriginal, date: date(2012)),
                FileDateEvidence(source: .exifDigitized, date: date(2010)),
                FileDateEvidence(source: .tiffDateTime, date: date(2008)),
                FileDateEvidence(source: .filesystemModification, date: date(2015))
            ],
            now: date(2026)
        )

        XCTAssertEqual(item?.proposedDate, date(2008))
        XCTAssertEqual(item?.proposedSource, .tiffDateTime)
    }

    func testRepairsImplausibleFutureCreationDateUsingOldestValidDate() {
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: date(2024)),
                FileDateEvidence(source: .exifOriginal, date: date(2030))
            ],
            now: date(2026)
        )

        XCTAssertEqual(item?.proposedDate, date(2024))
        XCTAssertEqual(item?.proposedSource, .filesystemCreation)
    }

    func testRepairsEmbeddedDatesWhenFilesystemCreationIsAlreadyOldest() {
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: date(2005)),
                FileDateEvidence(source: .exifOriginal, date: date(2012)),
                FileDateEvidence(source: .exifDigitized, date: date(2010)),
                FileDateEvidence(source: .filesystemModification, date: date(2024))
            ],
            now: date(2026)
        )

        XCTAssertEqual(item?.proposedDate, date(2005))
        XCTAssertEqual(item?.proposedSource, .filesystemCreation)
        XCTAssertEqual(item?.newestDisagreeingDate, date(2024))
    }

    func testDoesNotRepairWhenAllDatesAlreadyMatch() {
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: date(2005)),
                FileDateEvidence(source: .exifOriginal, date: date(2005)),
                FileDateEvidence(source: .tiffDateTime, date: date(2005)),
                FileDateEvidence(source: .filesystemModification, date: date(2005))
            ],
            now: date(2026)
        )

        XCTAssertNil(item)
    }

    func testRepairsWhenOnlyModificationDateDiffers() {
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: date(2005)),
                FileDateEvidence(source: .exifOriginal, date: date(2005)),
                FileDateEvidence(source: .tiffDateTime, date: date(2005)),
                FileDateEvidence(source: .filesystemModification, date: date(2024))
            ],
            now: date(2026)
        )

        XCTAssertEqual(item?.proposedDate, date(2005))
        XCTAssertEqual(item?.proposedSource, .filesystemCreation)
        XCTAssertEqual(item?.newestDisagreeingDate, date(2024))
    }

    func testEmbeddedSyncSkippedWhenEmbeddedDatesAlreadyMatchTarget() {
        let target = date(2015)
        XCTAssertFalse(
            FileDateRepairPlanner.embeddedCreationDatesNeedSync(
                [
                    FileDateEvidence(source: .filesystemCreation, date: date(2026)),
                    FileDateEvidence(source: .filesystemModification, date: target),
                    FileDateEvidence(source: .exifOriginal, date: target),
                    FileDateEvidence(source: .exifDigitized, date: target)
                ],
                target: target
            )
        )
        XCTAssertTrue(
            FileDateRepairPlanner.embeddedCreationDatesNeedSync(
                [
                    FileDateEvidence(source: .filesystemCreation, date: date(2026)),
                    FileDateEvidence(source: .filesystemModification, date: target),
                    FileDateEvidence(source: .exifOriginal, date: date(2012))
                ],
                target: target
            )
        )
    }

    private func date(_ year: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))!
    }
}

final class FileDateRepairExtensionTests: XCTestCase {
    func testNormalizesFlexibleExtensionList() {
        let value = FileDateRepairExtensions.normalizedString(" .JPG, heic;MOV\njpg ")

        XCTAssertEqual(value, "heic, jpg, mov")
        XCTAssertTrue(
            FileDateRepairExtensions.supports(
                URL(fileURLWithPath: "/tmp/PHOTO.JPG"),
                extensions: FileDateRepairExtensions.parse(value)
            )
        )
    }

    func testChunkerSkipsAttemptedItems() {
        let items = (1...5).map(makeItem)
        let chunk = FileDateRepairChunker.next(
            from: items,
            attemptedIDs: [items[0].id, items[2].id],
            size: 2
        )

        XCTAssertEqual(chunk.map(\.id), [items[1].id, items[3].id])
    }

    private func makeItem(_ index: Int) -> FileDateRepairItem {
        FileDateRepairItem(
            relativePath: "\(index).jpg",
            fileURL: URL(fileURLWithPath: "/tmp/\(index).jpg"),
            currentCreationDate: Date(timeIntervalSince1970: 200),
            proposedDate: Date(timeIntervalSince1970: 100),
            proposedSource: .filesystemModification,
            evidence: []
        )
    }
}

final class FileDateRepairScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDateRepairTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testSkipsHiddenPackagesSymlinksAndUnsupportedFiles() async throws {
        try makeRepairCandidate("visible.jpg")
        try makeRepairCandidate(".hidden.jpg")
        try makeRepairCandidate("notes.txt")

        let hiddenDirectory = root.appendingPathComponent(".hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        try makeRepairCandidate(".hidden/inside.jpg")

        let package = root.appendingPathComponent("Archive.app", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try makeRepairCandidate("Archive.app/inside.jpg")

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.jpg"),
            withDestinationURL: root.appendingPathComponent("visible.jpg")
        )

        let result = try await FileDateRepairScanner.scan(
            directory: root,
            supportedExtensions: ["jpg"],
            progress: { _ in }
        )

        XCTAssertEqual(result.scannedFileCount, 1)
        XCTAssertEqual(result.items.map(\.relativePath), ["visible.jpg"])
    }

    func testScanHonorsCancellation() async throws {
        for index in 0..<100 {
            try makeRepairCandidate("\(index).jpg")
        }

        let task = Task {
            try await FileDateRepairScanner.scan(
                directory: root,
                supportedExtensions: ["jpg"],
                progress: { _ in }
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    private func makeRepairCandidate(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2005:01:01 00:00:00"
            ]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

final class FileDatePreservationRepairTests: XCTestCase {
    func testAppliesCreatedAndModifiedDatesTogether() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDatePreservation-\(UUID().uuidString).jpg")
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let target = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2005, month: 2, day: 1))!
        try FileDatePreservation.applyFileDates(to: url, created: target, modified: target)
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let actualCreation = try XCTUnwrap(values.creationDate)
        let actualModification = try XCTUnwrap(values.contentModificationDate)
        XCTAssertEqual(actualCreation.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(actualModification.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1)
    }

    func testCreationOnlyRepairPreservesModificationDate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDatePreservation-\(UUID().uuidString).jpg")
        try Data("fixture".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let calendar = Calendar(identifier: .gregorian)
        let modified = calendar.date(from: DateComponents(year: 2015, month: 4, day: 3))!
        let proposedCreation = calendar.date(from: DateComponents(year: 2005, month: 2, day: 1))!
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)

        try FileDatePreservation.applyCreationDate(proposedCreation, to: url)

        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let actualCreation = try XCTUnwrap(values.creationDate)
        let actualModification = try XCTUnwrap(values.contentModificationDate)
        XCTAssertEqual(actualCreation.timeIntervalSince1970, proposedCreation.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(actualModification.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 1)
    }

    func testSynchronizesAllExistingImageCreationDates() async throws {
        let url = try makeTemporaryImage(
            pathExtension: "tiff",
            uti: "public.tiff",
            properties: [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2012:01:01 00:00:00",
                    kCGImagePropertyExifDateTimeDigitized: "2010:01:01 00:00:00"
                ],
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFDateTime: "2008:01:01 00:00:00"
                ]
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let target = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2005, month: 2, day: 3, hour: 4, minute: 5, second: 6)
        )!
        try FileDatePreservation.synchronizeImageCreationDates(in: url, to: target)

        let evidence = try await MediaMetadataReader.readDateEvidence(url: url, isVideo: false)
        for source in [FileDateSource.exifOriginal, .exifDigitized, .tiffDateTime] {
            let actual = try XCTUnwrap(
                evidence.first(where: { $0.source == source })?.date,
                "Missing \(source); evidence: \(evidence)"
            )
            XCTAssertEqual(actual.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testSynchronizesJPEGCreationDatesWithoutLeavingStaleValues() async throws {
        let url = try makeTemporaryImage(
            pathExtension: "jpg",
            uti: "public.jpeg",
            properties: [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2012:06:15 12:30:00",
                    kCGImagePropertyExifDateTimeDigitized: "2011:06:15 12:30:00"
                ],
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFDateTime: "2010:06:15 12:30:00"
                ]
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let target = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2004, month: 3, day: 4, hour: 5, minute: 6, second: 7)
        )!
        try FileDatePreservation.synchronizeImageCreationDates(in: url, to: target)

        let evidence = try await MediaMetadataReader.readDateEvidence(url: url, isVideo: false)
        let embedded = evidence.filter(\.source.isEmbeddedCreationDate)
        XCTAssertFalse(embedded.isEmpty)
        for item in embedded {
            XCTAssertEqual(
                item.date.timeIntervalSince1970,
                target.timeIntervalSince1970,
                accuracy: 1,
                "Stale \(item.source) remained after sync"
            )
        }
    }

    func testRemovesStaleDigitizedWhenImageIOWillNotUpdateIt() async throws {
        let url = try makeTemporaryImage(
            pathExtension: "jpg",
            uti: "public.jpeg",
            properties: [
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifDateTimeOriginal: "2015:02:22 20:45:00",
                    kCGImagePropertyExifDateTimeDigitized: "2012:01:01 00:00:00"
                ]
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let target = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2015, month: 2, day: 22, hour: 20, minute: 45)
        )!
        try FileDatePreservation.synchronizeImageCreationDates(in: url, to: target)

        let evidence = try await MediaMetadataReader.readDateEvidence(url: url, isVideo: false)
        if let digitized = evidence.first(where: { $0.source == .exifDigitized })?.date {
            XCTAssertEqual(digitized.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1)
        }
        for item in evidence where item.source.isEmbeddedCreationDate {
            XCTAssertEqual(item.date.timeIntervalSince1970, target.timeIntervalSince1970, accuracy: 1)
        }
    }

    private func makeTemporaryImage(
        pathExtension: String,
        uti: String,
        properties: [CFString: Any]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDateMetadata-\(UUID().uuidString).\(pathExtension)")
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

final class FileDateRepairVerificationTests: XCTestCase {
    func testAllowsDroppedEmbeddedSourcesWhenRemainingDatesMatch() {
        let target = Date(timeIntervalSince1970: 1_000)
        let failure = FileDateRepairVerification.validate(
            [
                FileDateEvidence(source: .filesystemCreation, date: target),
                FileDateEvidence(source: .filesystemModification, date: target),
                FileDateEvidence(source: .exifOriginal, date: target)
            ],
            expectedEmbeddedSources: [.exifOriginal, .tiffDateTime],
            target: target
        )

        XCTAssertNil(failure)
    }

    func testRejectsStaleEmbeddedDate() {
        let target = Date(timeIntervalSince1970: 1_000)
        let failure = FileDateRepairVerification.validate(
            [
                FileDateEvidence(source: .filesystemCreation, date: target),
                FileDateEvidence(source: .filesystemModification, date: target),
                FileDateEvidence(source: .exifOriginal, date: Date(timeIntervalSince1970: 500))
            ],
            expectedEmbeddedSources: [.exifOriginal],
            target: target
        )

        XCTAssertEqual(failure, .embeddedDateMismatch(.exifOriginal))
    }

    func testRejectsCompleteLossOfEmbeddedDates() {
        let target = Date(timeIntervalSince1970: 1_000)
        let failure = FileDateRepairVerification.validate(
            [
                FileDateEvidence(source: .filesystemCreation, date: target),
                FileDateEvidence(source: .filesystemModification, date: target)
            ],
            expectedEmbeddedSources: [.exifOriginal],
            target: target
        )

        XCTAssertEqual(failure, .embeddedDatesMissing)
    }

    func testRejectsStaleModificationDate() {
        let target = Date(timeIntervalSince1970: 1_000)
        let failure = FileDateRepairVerification.validate(
            [
                FileDateEvidence(source: .filesystemCreation, date: target),
                FileDateEvidence(source: .filesystemModification, date: Date(timeIntervalSince1970: 2_000))
            ],
            expectedEmbeddedSources: [],
            target: target
        )

        XCTAssertEqual(failure, .modificationDateMismatch)
    }
}
