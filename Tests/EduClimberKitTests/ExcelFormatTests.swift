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

    // MARK: - Excel 97-2003 binary (.xls)

    func testLegacyBinaryExcelConverts() throws {
        let table = try Pipeline.loadSource(at: fixture("legacy_export.xls"))
        XCTAssertEqual(
            table.headers,
            ["First Name", "Last Name", "Student ID", "Grade Level",
             "Reading Level (A-Z)", "Proficiency Level"])

        let result = try Pipeline.convertFile(
            converter: converter, url: fixture("legacy_export.xls"), answers: answers)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows[0]["Student First Name"], "Maria")
        XCTAssertEqual(result.rows[0]["Student Last Name"], "Gomez")
        // A numeric cell must not arrive as "100234.0".
        XCTAssertEqual(result.rows[0]["Student ID"], "100234")
        XCTAssertEqual(result.rows[0]["Score"], "1")
        XCTAssertEqual(result.rows[1]["Student Last Name"], "Van Dyke")
        XCTAssertEqual(result.rows[1]["Student Grade Level"], "3")
        XCTAssertEqual(result.rows[2]["Student First Name"], "José")
        XCTAssertEqual(result.rows[2]["Student Last Name"], "O'Brien")
    }

    /// The blank row is row 4 in Excel, so the bad row after it is row 6.
    func testLegacyBinaryRowNumbersMatchExcel() throws {
        let result = try Pipeline.convertFile(
            converter: converter, url: fixture("legacy_export.xls"), answers: answers)
        XCTAssertEqual(result.skippedRowCount, 1)
        XCTAssertEqual(result.issues.first?.rowNumber, 6)
        XCTAssertTrue(
            result.issues[0].summary.contains("'QQ' is not in the reading level table"),
            result.issues[0].summary)
    }

    /// A shared string table large enough to span CONTINUE records: strings must
    /// not be truncated or shifted where the records join.
    func testLegacyBinaryWithLargeStringTable() throws {
        let result = try Pipeline.convertFile(
            converter: converter, url: fixture("legacy_big.xls"), answers: answers)
        XCTAssertTrue(result.isClean, "\(result.issuesReport())")
        XCTAssertEqual(result.rows.count, 399)

        let first = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(first["Student First Name"], "Given1-" + String(repeating: "x", count: 20))
        XCTAssertEqual(first["Student Last Name"], "Family1-" + String(repeating: "y", count: 20))
        XCTAssertEqual(first["Student ID"], "200001")

        let last = try XCTUnwrap(result.rows.last)
        XCTAssertEqual(last["Student First Name"], "Given399-" + String(repeating: "x", count: 20))
        XCTAssertEqual(last["Student ID"], "200399")
        XCTAssertFalse(last["Reading Level"]?.isEmpty ?? true)
    }

    func testDamagedBinaryWorkbookIsReportedNotCrashed() {
        // Header bytes only: correctly identified as a .xls, but there is no
        // workbook inside to read.
        XCTAssertThrowsError(try Pipeline.loadSource(at: fixture("legacy_biff.xls"))) { error in
            let message = (error as? SourceFileError)?.errorDescription ?? ""
            XCTAssertTrue(message.lowercased().contains("could not be read"), message)
        }
    }

    func testRKNumberDecoding() {
        // Integer RK: value 100234 shifted left two bits, integer flag set.
        let integerRK = UInt32(100234) << 2 | 0x02
        XCTAssertEqual(XLSReader.decodeRK(integerRK), "100234")
        // The same, scaled by 100.
        XCTAssertEqual(XLSReader.decodeRK(UInt32(250) << 2 | 0x03), "2.5")
    }
}
