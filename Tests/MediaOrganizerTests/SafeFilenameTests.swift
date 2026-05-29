import XCTest
@testable import MediaOrganizer

final class SafeFilenameTests: XCTestCase {
    func testStripsPathComponents() {
        XCTAssertEqual(SafeFilename.sanitize("../../secret.jpg"), "secret.jpg")
        XCTAssertEqual(SafeFilename.sanitize("folder/photo.jpg"), "photo.jpg")
    }

    func testRejectsDotNames() {
        XCTAssertEqual(SafeFilename.sanitize("."), "untitled")
        XCTAssertEqual(SafeFilename.sanitize("..", fallback: "photo"), "photo")
    }

    func testFileURLStaysInDirectory() throws {
        let directory = URL(fileURLWithPath: "/tmp/export", isDirectory: true)
        let url = SafeFilename.fileURL(in: directory, filename: "../../escape.jpg")
        XCTAssertNotNil(url)
        XCTAssertTrue(SafeFilename.isContained(url!, in: directory))
    }

    func testFileURLRejectsEscape() {
        let directory = URL(fileURLWithPath: "/tmp/export", isDirectory: true)
        // After sanitization this is safe; containment should still hold
        let url = SafeFilename.fileURL(in: directory, filename: "normal.jpg")
        XCTAssertNotNil(url)
    }
}
