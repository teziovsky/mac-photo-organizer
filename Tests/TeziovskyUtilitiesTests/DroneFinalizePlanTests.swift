import XCTest
@testable import TeziovskyUtilities

final class DroneFinalizePlanTests: XCTestCase {
    private let config = DroneFinalizeConfig.default

    /// Treats common photo/video extensions as media without depending on UTType.
    private func isMedia(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mov", "mp4", "m4v", "jpg", "jpeg", "png", "heic", "dng", "raw"].contains(ext)
    }

    private func makePlan(_ files: [String], config: DroneFinalizeConfig? = nil) -> DroneFinalizePlan {
        DroneFinalizePlanBuilder.makePlan(
            exportFiles: files,
            config: config ?? self.config,
            isMedia: isMedia
        )
    }

    func testMatchesCompressedToSourceAndDropsSuffix() {
        let plan = makePlan(["clip.mov", "clip_COMPRESSED.mp4"])
        XCTAssertEqual(plan.matchedPairs.count, 1)
        let pair = plan.matchedPairs[0]
        XCTAssertEqual(pair.sourceName, "clip.mov")
        XCTAssertEqual(pair.compressedName, "clip_COMPRESSED.mp4")
        XCTAssertEqual(pair.finalName, "clip.mp4")
        XCTAssertTrue(plan.unmatchedCompressed.isEmpty)
        XCTAssertTrue(plan.passthroughMedia.isEmpty)
    }

    func testSameExtensionPairResolvesToSourceName() {
        let plan = makePlan(["clip.mp4", "clip_COMPRESSED.mp4"])
        XCTAssertEqual(plan.matchedPairs.count, 1)
        XCTAssertEqual(plan.matchedPairs[0].finalName, "clip.mp4")
    }

    func testUnmatchedCompressedIsRenamedOnly() {
        let plan = makePlan(["orphan_COMPRESSED.mp4"])
        XCTAssertTrue(plan.matchedPairs.isEmpty)
        XCTAssertEqual(plan.unmatchedCompressed.count, 1)
        XCTAssertEqual(plan.unmatchedCompressed[0].originalName, "orphan_COMPRESSED.mp4")
        XCTAssertEqual(plan.unmatchedCompressed[0].finalName, "orphan.mp4")
    }

    func testPassthroughAndLeftoverClassification() {
        let plan = makePlan(["photo.jpg", "notes.txt"])
        XCTAssertEqual(plan.passthroughMedia, ["photo.jpg"])
        XCTAssertEqual(plan.leftoverFiles, ["notes.txt"])
    }

    func testConflictWhenFinalNameCollidesWithUnrelatedFile() {
        // clip.mp4 is a different (unrelated) file from the source clip.mov.
        let plan = makePlan(["clip.mov", "clip.mp4", "clip_COMPRESSED.mp4"])
        XCTAssertEqual(plan.conflicts, ["clip_COMPRESSED.mp4"])
        XCTAssertTrue(plan.matchedPairs.isEmpty)
    }

    func testHiddenFilesAreIgnored() {
        let plan = makePlan([".DS_Store", "clip.mov", "clip_COMPRESSED.mp4"])
        XCTAssertEqual(plan.matchedPairs.count, 1)
        XCTAssertTrue(plan.leftoverFiles.isEmpty)
        XCTAssertTrue(plan.passthroughMedia.isEmpty)
    }

    func testFinalMediaNamesCollectsEverythingMovedUp() {
        let plan = makePlan([
            "a.mov", "a_COMPRESSED.mp4",
            "orphan_COMPRESSED.mp4",
            "photo.jpg",
        ])
        XCTAssertEqual(Set(plan.finalMediaNames), ["a.mp4", "orphan.mp4", "photo.jpg"])
    }

    func testCustomSuffix() {
        var custom = DroneFinalizeConfig.default
        custom.compressedSuffix = "-web"
        let plan = makePlan(["clip.mov", "clip-web.mp4"], config: custom)
        XCTAssertEqual(plan.matchedPairs.count, 1)
        XCTAssertEqual(plan.matchedPairs[0].finalName, "clip.mp4")
    }

    func testBlankSuffixFallsBackToDefault() {
        var custom = DroneFinalizeConfig.default
        custom.compressedSuffix = "   "
        let plan = makePlan(["clip.mov", "clip_COMPRESSED.mp4"], config: custom)
        XCTAssertEqual(plan.matchedPairs.count, 1)
        XCTAssertEqual(plan.matchedPairs[0].finalName, "clip.mp4")
    }

    func testNormalizesSupportedOutputExtension() {
        XCTAssertEqual(DroneFinalizeConfig.normalizeOutputExtension(" .MKV "), "mkv")
    }

    func testUnsupportedOutputExtensionFallsBackToMP4() {
        XCTAssertEqual(DroneFinalizeConfig.normalizeOutputExtension("avi"), "mp4")
    }

    func testHasWorkReflectsContent() {
        XCTAssertFalse(makePlan(["notes.txt"]).hasWork)
        XCTAssertTrue(makePlan(["photo.jpg"]).hasWork)
    }
}
