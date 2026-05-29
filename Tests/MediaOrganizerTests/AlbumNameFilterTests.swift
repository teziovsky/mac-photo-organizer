import XCTest
@testable import MediaOrganizer

final class AlbumNameFilterTests: XCTestCase {
    func testIncludesAlbumWithoutSuffix() {
        XCTAssertTrue(AlbumNameFilter.shouldInclude(albumName: "Holiday 2024", excludedSuffix: "_zgrane"))
    }

    func testExcludesAlbumWithSuffix() {
        XCTAssertFalse(AlbumNameFilter.shouldInclude(albumName: "Holiday 2024_zgrane", excludedSuffix: "_zgrane"))
    }

    func testEmptySuffixIncludesAll() {
        XCTAssertTrue(AlbumNameFilter.shouldInclude(albumName: "Anything_zgrane", excludedSuffix: "   "))
    }
}
