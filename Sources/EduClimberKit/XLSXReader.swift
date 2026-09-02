import Foundation

/// Reads the first worksheet of an .xlsx file into a `Table`.
///
/// Only what an export needs: shared and inline strings, numbers, and the cell
/// references that say which column a value belongs to (Excel omits empty cells).
public enum XLSXReader {
    public static func read(contentsOf url: URL) throws -> Table {
        let archive = try ZipArchive(contentsOf: url)
        let sharedStrings = try readSharedStrings(archive)
        let sheetPath = try firstWorksheetPath(archive)
        let grid = try readSheet(archive, path: sheetPath, sharedStrings: sharedStrings)
        return try makeTable(fromGrid: grid)
    }

    // MARK: - Workbook structure

    /// The path of the workbook's first sheet, following workbook.xml and its
    /// relationships; falls back to the conventional location.
    static func firstWorksheetPath(_ archive: ZipArchive) throws -> String {
        guard archive.contains("xl/workbook.xml") else {
            throw SourceFileError.malformedExcel("no workbook part")
        }
        let workbook = try archive.data(for: "xl/workbook.xml")
        let sheets = SimpleXML.elements(in: workbook, named: "sheet")
        let relationshipID = sheets.first?["r:id"] ?? sheets.first?["id"]

        if let relationshipID, archive.contains("xl/_rels/workbook.xml.rels") {
            let rels = try archive.data(for: "xl/_rels/workbook.xml.rels")
            for relationship in SimpleXML.elements(in: rels, named: "Relationship")
            where relationship["Id"] == relationshipID {
                if var target = relationship["Target"] {
                    if target.hasPrefix("/") { target.removeFirst() }
                    let path = target.hasPrefix("xl/") ? target : "xl/" + target
                    if archive.contains(path) { return path }
                }
            }
        }
        if archive.contains("xl/worksheets/sheet1.xml") { return "xl/worksheets/sheet1.xml" }
        throw SourceFileError.malformedExcel("no worksheet found")
    }

    static func readSharedStrings(_ archive: ZipArchive) throws -> [String] {
        guard archive.contains("xl/sharedStrings.xml") else { return [] }
        return SimpleXML.sharedStrings(in: try archive.data(for: "xl/sharedStrings.xml"))
    }

    // MARK: - Sheet

    static func readSheet(
        _ archive: ZipArchive, path: String, sharedStrings: [String]
    ) throws -> [[String]] {
        let sheet = try archive.data(for: path)
        return SimpleXML.sheetGrid(in: sheet, sharedStrings: sharedStrings)
    }

    /// "BD" -> 55. Cell references carry the column, so gaps stay aligned.
    static func columnIndex(fromReference reference: String) -> Int {
        var index = 0
        for character in reference.uppercased() {
            guard let ascii = character.asciiValue, ascii >= 65, ascii <= 90 else { break }
            index = index * 26 + Int(ascii - 64)
        }
        return max(0, index - 1)
    }

    /// Excel stores 100234 as "100234" but 3 as "3.0"; show whole numbers plainly
    /// so a Student ID does not arrive as "100234.0".
    static func formatNumber(_ text: String) -> String {
        guard let number = Double(text) else { return text }
        if number == number.rounded(), abs(number) < 1e15 {
            return String(Int64(number))
        }
        return text
    }
}
