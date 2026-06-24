import XCTest
@testable import TeziovskyUtilities

final class DroneProjectValidatorTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("drone-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testInvalidWhenRawMissing() {
        try? FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("export", isDirectory: true),
            withIntermediateDirectories: true
        )
        let result = DroneProjectValidator.validate(projectDirectory: tempRoot, config: .default)
        XCTAssertEqual(result.status, .invalid)
    }

    func testValidFlatLayout() throws {
        try createLayout(vertical: false, horizontal: false)
        let result = DroneProjectValidator.validate(projectDirectory: tempRoot, config: .default)
        XCTAssertEqual(result.status, .valid)
        XCTAssertEqual(result.layoutMode, .flat)
    }

    func testValidWithVerticalOnly() throws {
        try createLayout(vertical: true, horizontal: false)
        let result = DroneProjectValidator.validate(projectDirectory: tempRoot, config: .default)
        XCTAssertTrue(result.canContinue)
        XCTAssertEqual(result.layoutMode, .oriented(vertical: true, horizontal: false))
    }

    func testWarningWhenExportVerticalMissing() throws {
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("raw/vertical", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("export", isDirectory: true),
            withIntermediateDirectories: true
        )
        let result = DroneProjectValidator.validate(projectDirectory: tempRoot, config: .default)
        XCTAssertEqual(result.status, .validWithWarnings)
    }

    private func createLayout(vertical: Bool, horizontal: Bool) throws {
        for folder in ["raw", "export"] {
            let base = tempRoot.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            if vertical {
                try FileManager.default.createDirectory(
                    at: base.appendingPathComponent("vertical", isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            if horizontal {
                try FileManager.default.createDirectory(
                    at: base.appendingPathComponent("horizontal", isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
        }
    }
}

final class DroneExportScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("drone-scan-\(UUID().uuidString)", isDirectory: true)
        let export = tempRoot.appendingPathComponent("export/vertical", isDirectory: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: export.appendingPathComponent("scene.mov").path,
            contents: Data([0x00])
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testFindsUncompressedExport() throws {
        let pending = try DroneExportScanner.uncompressedExports(
            projectDirectory: tempRoot,
            config: .default
        )
        XCTAssertEqual(pending.map(\.relativePath), ["vertical/scene.mov"])
    }

    func testSkipsWhenCompressedTwinExists() throws {
        let export = tempRoot.appendingPathComponent("export/vertical", isDirectory: true)
        FileManager.default.createFile(
            atPath: export.appendingPathComponent("scene_COMPRESSED.mp4").path,
            contents: Data([0x00])
        )
        let pending = try DroneExportScanner.uncompressedExports(
            projectDirectory: tempRoot,
            config: .default
        )
        XCTAssertTrue(pending.isEmpty)
    }
}

final class DroneRelativeFinalizePlanTests: XCTestCase {
    private func isMedia(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mov", "mp4"].contains(ext)
    }

    func testMatchesWithinSameSubdirectory() {
        let plan = DroneFinalizePlanBuilder.makePlan(
            exportFiles: [
                "vertical/clip.mov",
                "vertical/clip_COMPRESSED.mp4",
            ],
            config: .default,
            isMedia: isMedia
        )
        XCTAssertEqual(plan.matchedPairs.count, 1)
        XCTAssertEqual(plan.matchedPairs[0].finalRelativePath, "vertical/clip.mp4")
    }

    func testDoesNotMatchAcrossSubdirectories() {
        let plan = DroneFinalizePlanBuilder.makePlan(
            exportFiles: [
                "vertical/clip.mov",
                "horizontal/clip_COMPRESSED.mp4",
            ],
            config: .default,
            isMedia: isMedia
        )
        XCTAssertTrue(plan.matchedPairs.isEmpty)
        XCTAssertEqual(plan.unmatchedCompressed.count, 1)
    }
}

final class HandBrakeCompressorTests: XCTestCase {
    func testParsesPlainPresetList() {
        let presets = HandBrakeCompressor.parsePresetNames(from: """
        Presets:
        Fast 1080p30
        HQ 1080p30 Surround
        """)
        XCTAssertEqual(presets, ["Fast 1080p30", "HQ 1080p30 Surround"])
    }
}
