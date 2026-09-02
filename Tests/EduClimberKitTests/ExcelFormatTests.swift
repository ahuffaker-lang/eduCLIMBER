import XCTest
@testable import EduClimberKit

/// Exports arrive labelled loosely: a file named `.xls` is often an HTML table
/// or an XML spreadsheet, and a real .xlsx sometimes carries an .xls name. The
/// app decides by content, so all of these have to convert.
final class ExcelFormatTests: XCTestCase {
    let converter = RunningRecordsConverter()
    let answers = ["assessment_window": "Trimester 1", "school_year": "2026-2027"]

    func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    // MARK: - Detection

    func testFormatDetectionIgnoresTheFileName() throws {
        XCTAssertEqual(try SourceFormat.detect(at: fixture("sample_export.xlsx")), .xlsx)
        XCTAssertEqual(try SourceFormat.detect(at: fixture("renamed_xlsx.xls")), .xlsx)
        XCTAssertEqual(try SourceFormat.detect(at: fixture("html_export.xls")), .htmlTable)
        XCTAssertEqual(
            try SourceFormat.detect(at: fixture("spreadsheetml_export.xls")), .spreadsheetML)
        XCTAssertEqual(try SourceFormat.detect(at: fixture("legacy_biff.xls")), .legacyExcel)
    }

    func testPlainTextIsTreatedAsDelimited() {
        let csv = Data("Student,Student ID\n\"Gomez, Maria\",1\n".utf8)
        XCTAssertEqual(SourceFormat.detect(head: csv, fileExtension: ""), .delimitedText)
        XCTAssertEqual(SourceFormat.detect(head: csv, fileExtension: "dat"), .delimitedText)
    }

    func testPDFIsRejectedClearly() {
        XCTAssertEqual(
            SourceFormat.detect(head: Data("%PDF-1.7\n".utf8), fileExtension: "pdf"), .pdf)
    }

    // MARK: - An .xlsx wearing an .xls name

    func testRenamedXLSXConverts() throws {
        let result = try Pipeline.convertFile(
            converter: converter, url: fixture("renamed_xlsx.xls"), answers: answers)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Gomez")
    }

    // MARK: - HTML pretending to be Excel

    func testHTMLTableExportConverts() throws {
        let table = try Pipeline.loadSource(at: fixture("html_export.xls"))
        XCTAssertEqual(
            table.headers,
            ["First Name", "Last Name", "Student ID", "Grade Level",
             "Reading Level (A-Z)", "Proficiency Level"])
        XCTAssertEqual(table.rows.count, 3)

        let result = try Pipeline.convertFile(
            converter: converter, url: fixture("html_export.xls"), answers: answers)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows[0]["Student First Name"], "Maria")
        // &nbsp; inside a cell must not survive into the upload.
        XCTAssertEqual(result.rows[0]["Reading Level"], "Below A")
        XCTAssertEqual(result.rows[0]["Score"], "1")
        XCTAssertEqual(result.rows[1]["Student Last Name"], "Van Dyke")
        // Numeric and quote entities decode.
        XCTAssertEqual(result.rows[2]["Student First Name"], "José")
        XCTAssertEqual(result.rows[2]["Student Last Name"], "O'Brien")
    }

    func testHTMLEntityAndTagCleaning() {
        XCTAssertEqual(HTMLTableReader.clean("<b>Maria</b>"), "Maria")
        XCTAssertEqual(HTMLTableReader.clean("Below&nbsp;A"), "Below A")
        XCTAssertEqual(HTMLTableReader.clean("a<br>b"), "a b")
        XCTAssertEqual(HTMLTableReader.clean("Jos&#233;"), "José")
        XCTAssertEqual(HTMLTableReader.clean("R&amp;D &lt;tag&gt;"), "R&D <tag>")
        XCTAssertEqual(HTMLTableReader.clean("O&#x27;Brien"), "O'Brien")
    }

    func testLayoutTablesDoNotWinOverTheDataTable() {
        let html = """
        <html><body>
        <table><tr><td>Report header</td></tr></table>
        <table>
          <tr><th>A</th><th>B</th></tr>
          <tr><td>1</td><td>2</td></tr>
          <tr><td>3</td><td>4</td></tr>
        </table>
        </body></html>
        """
        let grid = HTMLTableReader.parse(html)
        XCTAssertEqual(grid.count, 3)
        XCTAssertEqual(grid[0], ["A", "B"])
        XCTAssertEqual(grid[2], ["3", "4"])
    }

    // MARK: - Excel 2003 XML

    func testSpreadsheetMLExportConverts() throws {
        let table = try Pipeline.loadSource(at: fixture("spreadsheetml_export.xls"))
        XCTAssertEqual(table.headers.first, "First Name")
        XCTAssertEqual(table.rows.count, 2)

        let result = try Pipeline.convertFile(
            converter: converter, url: fixture("spreadsheetml_export.xls"), answers: answers)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows[0]["Student ID"], "100234")
        XCTAssertEqual(result.rows[0]["Score"], "1")
        // ss:Index skips an empty cell, so the level must not shift a column left.
        XCTAssertEqual(result.rows[1]["Student Last Name"], "Okafor")
        XCTAssertEqual(result.rows[1]["Reading Level"], "J")
    }

    // MARK: - The one format that really cannot be read

    func testLegacyBinaryExcelExplainsWhatToDo() {
        XCTAssertThrowsError(try Pipeline.loadSource(at: fixture("legacy_biff.xls"))) { error in
            let message = (error as? SourceFileError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("Excel 97-2003"), message)
            XCTAssertTrue(message.contains("Save As"), message)
        }
    }
}
