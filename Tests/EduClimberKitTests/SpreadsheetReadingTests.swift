import XCTest
@testable import EduClimberKit

/// Reading the two source formats: CSV quirks and real .xlsx files.
final class SpreadsheetReadingTests: XCTestCase {
    let converter = RunningRecordsConverter()
    let answers = ["assessment_window": "Trimester 1", "school_year": "2026-2027"]

    var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EduClimberKitTests
            .deletingLastPathComponent()   // Tests
            .appendingPathComponent("Fixtures/sample_export.xlsx")
    }

    // MARK: - CSV

    func testQuotedFieldsAndEmbeddedCommas() {
        let rows = CSVReader.parse("a,\"b,c\",d\n1,\"say \"\"hi\"\"\",3\n")
        XCTAssertEqual(rows[0], ["a", "b,c", "d"])
        XCTAssertEqual(rows[1], ["1", "say \"hi\"", "3"])
    }

    func testCarriageReturnLineEndings() {
        XCTAssertEqual(CSVReader.parse("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSVReader.parse("a,b\r1,2"), [["a", "b"], ["1", "2"]])
    }

    func testQuotedFieldFollowedByCRLF() {
        // The closing quote is followed by the CRLF grapheme, which must still
        // end the row rather than land inside the next field.
        XCTAssertEqual(
            CSVReader.parse("\"a\",\"b\"\r\n\"c\",\"d\"\r\n"), [["a", "b"], ["c", "d"]])
    }

    func testEmbeddedNewlineInsideQuotes() {
        XCTAssertEqual(CSVReader.parse("a,\"line1\nline2\"\n"), [["a", "line1\nline2"]])
    }

    func testTabDelimitedIsDetected() {
        let text = "Student\tStudent ID\nGomez, Maria\t123\n"
        XCTAssertEqual(CSVReader.detectDelimiter(in: text), "\t")
    }

    func testBOMIsStripped() {
        XCTAssertEqual(CSVReader.stripBOM("\u{FEFF}Student"), "Student")
    }

    // MARK: - XLSX

    func testReadsRealExcelFile() throws {
        let table = try XLSXReader.read(contentsOf: fixtureURL)
        XCTAssertEqual(
            table.headers,
            ["Student", "Student ID", "Grade Level", "Reading Level (A-Z)", "Proficiency Level"])
        XCTAssertEqual(table.rows.count, 3)  // the blank spacer row is dropped
        XCTAssertEqual(table.value(table.rows[0], "Student"), "Gomez, Maria")
        // A numeric cell must not arrive as "100234.0".
        XCTAssertEqual(table.value(table.rows[0], "Student ID"), "100234")
        XCTAssertEqual(table.value(table.rows[0], "Grade Level"), "K")
        XCTAssertEqual(table.value(table.rows[1], "Grade Level"), "2")
    }

    func testExcelRowNumbersSurviveBlankRows() throws {
        let table = try XLSXReader.read(contentsOf: fixtureURL)
        let result = try Pipeline.convertFile(
            converter: converter, url: fixtureURL, answers: answers)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.errors.count, 1)
        // "Ray, Jo" is on spreadsheet row 5, counting the blank row 3.
        XCTAssertEqual(result.errors.first?.rowNumber, 5)
        XCTAssertTrue(
            result.errors[0].message.contains("'QQ' is not in the reading level table"),
            result.errors[0].message)
        XCTAssertEqual(table.firstDataRowNumber, 2)
    }

    func testColumnIndexFromCellReference() {
        XCTAssertEqual(XLSXReader.columnIndex(fromReference: "A1"), 0)
        XCTAssertEqual(XLSXReader.columnIndex(fromReference: "E12"), 4)
        XCTAssertEqual(XLSXReader.columnIndex(fromReference: "AA3"), 26)
        XCTAssertEqual(XLSXReader.columnIndex(fromReference: "BD55"), 55)
    }

    func testNumberFormatting() {
        XCTAssertEqual(XLSXReader.formatNumber("100234"), "100234")
        XCTAssertEqual(XLSXReader.formatNumber("2.0"), "2")
        XCTAssertEqual(XLSXReader.formatNumber("2.5"), "2.5")
        XCTAssertEqual(XLSXReader.formatNumber("K"), "K")
    }

    func testZipReaderFindsWorkbookParts() throws {
        let archive = try ZipArchive(contentsOf: fixtureURL)
        XCTAssertTrue(archive.contains("xl/workbook.xml"))
        let sheetPath = try XLSXReader.firstWorksheetPath(archive)
        XCTAssertTrue(sheetPath.hasPrefix("xl/worksheets/"), sheetPath)
        let xml = try archive.data(for: sheetPath)
        XCTAssertTrue(
            String(data: xml, encoding: .utf8)?.contains("<worksheet") ?? false,
            "decompressed sheet XML should be readable")
    }

    /// The file has to exist to be sniffed -- an extension alone decides nothing
    /// now, so a missing file reports exactly that. What each real format does is
    /// covered in ExcelFormatTests.
    func testMissingFileIsReportedAsUnreadable() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).xls")
        XCTAssertThrowsError(try Pipeline.loadSource(at: missing)) { error in
            guard case .unreadable = (error as? SourceFileError) else {
                return XCTFail("expected .unreadable, got \(error)")
            }
        }
    }
}
