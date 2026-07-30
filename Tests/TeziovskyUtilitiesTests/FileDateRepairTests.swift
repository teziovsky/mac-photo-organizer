import Foundation
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

        XCTAssertEqual(item?.proposedCreationDate, exif)
        XCTAssertEqual(item?.proposedSource, .exifOriginal)
        XCTAssertEqual(item?.currentCreationDate, created)
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

    func testIgnoresImplausibleFutureDate() {
        let item = FileDateRepairPlanner.makeItem(
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            relativePath: "photo.jpg",
            evidence: [
                FileDateEvidence(source: .filesystemCreation, date: date(2024)),
                FileDateEvidence(source: .exifOriginal, date: date(2030))
            ],
            now: date(2026)
        )

        XCTAssertNil(item)
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
            proposedCreationDate: Date(timeIntervalSince1970: 100),
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
        try Data().write(to: url)
        let oldDate = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2005, month: 1, day: 1)
        )!
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
    }
}

final class FileDatePreservationRepairTests: XCTestCase {
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
}
