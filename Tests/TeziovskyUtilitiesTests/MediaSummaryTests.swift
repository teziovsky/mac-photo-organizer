import XCTest
@testable import TeziovskyUtilities

final class MediaSummaryTests: XCTestCase {
    func testSummaryFromCounts() {
        XCTAssertEqual(MediaSummary.text(photoCount: 2, videoCount: 1, mediaCount: 3), "2 photos, 1 video")
    }

    func testSummaryFromItems() {
        let items = [
            MediaItem(id: "1", filename: "a.jpg", isVideo: false, creationDate: nil),
            MediaItem(id: "2", filename: "b.mov", isVideo: true, creationDate: nil),
        ]
        XCTAssertEqual(MediaSummary.text(for: items), "1 photo, 1 video")
    }
}
