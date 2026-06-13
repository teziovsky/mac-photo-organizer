import Foundation

enum OrganizeExportDirectory {
    private static let yearPattern = #/(19|20)\d{2}/#

    static func nameContainsYear(_ name: String) -> Bool {
        name.contains(yearPattern)
    }

    static func exportDirectory(
        base: URL,
        selectedDirectoryName: String,
        creationDate: Date,
        organizeByYearEnabled: Bool
    ) -> URL {
        guard organizeByYearEnabled, !nameContainsYear(selectedDirectoryName) else {
            return base
        }
        let year = Calendar.current.component(.year, from: creationDate)
        return base.appendingPathComponent(String(year), isDirectory: true)
    }
}
