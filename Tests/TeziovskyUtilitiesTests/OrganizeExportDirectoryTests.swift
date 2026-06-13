import XCTest
@testable import TeziovskyUtilities

final class OrganizeExportDirectoryTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/tmp/photos", isDirectory: true)

    private func date(year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = 3
        components.day = 15
        return Calendar.current.date(from: components)!
    }

    func testNameContainsYearMatchesPlainYear() {
        XCTAssertTrue(OrganizeExportDirectory.nameContainsYear("2026"))
    }

    func testNameContainsYearMatchesPartialYear() {
        XCTAssertTrue(OrganizeExportDirectory.nameContainsYear("2026_10_test"))
        XCTAssertTrue(OrganizeExportDirectory.nameContainsYear("2026_10"))
    }

    func testNameContainsYearMatchesYearInPhrase() {
        XCTAssertTrue(OrganizeExportDirectory.nameContainsYear("Holiday 2024"))
    }

    func testNameContainsYearRejectsNamesWithoutYear() {
        XCTAssertFalse(OrganizeExportDirectory.nameContainsYear("photos"))
        XCTAssertFalse(OrganizeExportDirectory.nameContainsYear("Room 101"))
    }

    func testExportDirectoryWhenSettingOffReturnsBase() {
        let result = OrganizeExportDirectory.exportDirectory(
            base: base,
            selectedDirectoryName: "photos",
            creationDate: date(year: 2024),
            organizeByYearEnabled: false
        )
        XCTAssertEqual(result, base)
    }

    func testExportDirectoryWhenSettingOnAndNameHasYearReturnsBase() {
        let result = OrganizeExportDirectory.exportDirectory(
            base: base,
            selectedDirectoryName: "2026_10_test",
            creationDate: date(year: 2024),
            organizeByYearEnabled: true
        )
        XCTAssertEqual(result, base)
    }

    func testExportDirectoryWhenSettingOnAndNameHasNoYearReturnsYearSubfolder() {
        let result = OrganizeExportDirectory.exportDirectory(
            base: base,
            selectedDirectoryName: "photos",
            creationDate: date(year: 2024),
            organizeByYearEnabled: true
        )
        XCTAssertEqual(result, base.appendingPathComponent("2024", isDirectory: true))
    }
}
