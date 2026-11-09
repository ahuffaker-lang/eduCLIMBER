import XCTest
@testable import EduClimberKit

/// Builds grids shaped like a real ELPAC Longitudinal Roster export, but with
/// invented students -- the real export has 49 columns (A-AW) and leaves most
/// of them blank. Column indices used here match the real export exactly:
/// C=2 Student Name, H=7 Student ID, N=13 English Prof., P=15 Test Purpose,
/// R=17 Academic Year, S=18 Test Grade Level, Z=25 Overall Performance Level.
final class ELPACLongitudinalReaderTests: XCTestCase {
    static func row(_ values: [Int: String]) -> [String] {
        var result = [String](repeating: "", count: 26)
        for (index, value) in values { result[index] = value }
        return result
    }

    static func studentRow(name: String, id: String, englishProficiency: String = "L") -> [String] {
        row([2: name, 7: id, 13: englishProficiency])
    }

    static func yearRow(
        testPurpose: String, academicYear: String, gradeLevel: String, overallLevel: String = ""
    ) -> [String] {
        row([15: testPurpose, 17: academicYear, 18: gradeLevel, 25: overallLevel])
    }

    let titleRow = ["ELPAC Longitudinal Roster"]

    let columnHeaderRow = row([
        2: "Student", 7: "Student ID", 13: "English\nProf.", 15: "Test Purpose",
        17: "Academic\nYear", 18: "Test\nGrade\nLevel",
    ])

    func footerRow(page: String = "Page 1 of 1") -> [String] {
        Self.row([2: "Generated on 11/08/2026\nby Renaissance Learning, Inc."])
    }

    // MARK: - Row classification

    func testClassifiesStudentRow() {
        let classified = ELPACLongitudinalReader.classify(
            Self.studentRow(name: "Abundis, Kataleah C.", id: "20212207"))
        XCTAssertEqual(
            classified,
            .student(name: "Abundis, Kataleah C.", studentID: "20212207", englishProficiency: "L"))
    }

    func testClassifiesYearRow() {
        let classified = ELPACLongitudinalReader.classify(
            Self.yearRow(testPurpose: "Summative", academicYear: "2024-25", gradeLevel: "01", overallLevel: "3L"))
        XCTAssertEqual(
            classified,
            .yearRow(
                testPurpose: "Summative", academicYear: "2024-25", gradeLevel: "01",
                overallPerformanceLevel: "3L"))
    }

    func testClassifiesColumnHeaderRowAsOther() {
        XCTAssertEqual(ELPACLongitudinalReader.classify(columnHeaderRow), .other)
    }

    func testClassifiesTitleRowAsOther() {
        XCTAssertEqual(ELPACLongitudinalReader.classify(titleRow), .other)
    }

    func testClassifiesFooterRowAsOther() {
        XCTAssertEqual(ELPACLongitudinalReader.classify(footerRow()), .other)
    }

    func testStudentIDMustBeAllDigits() {
        let classified = ELPACLongitudinalReader.classify(
            Self.row([2: "Student", 7: "Student ID"]))
        XCTAssertEqual(classified, .other)
    }

    func testAcademicYearMustMatchTheYYYYDashYYShape() {
        let classified = ELPACLongitudinalReader.classify(
            Self.row([15: "Summative", 17: "Academic Year", 18: "KN"]))
        XCTAssertEqual(classified, .other)
    }

    // MARK: - Flattening

    func testFlattenPicksTheMostRecentAcademicYear() throws {
        let grid = [
            Self.studentRow(name: "Abundis, Kataleah C.", id: "20212207"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2022-23", gradeLevel: "KN", overallLevel: "3H"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2023-24", gradeLevel: "KN", overallLevel: "3H"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2024-25", gradeLevel: "01", overallLevel: "3L"),
        ]
        let table = try ELPACLongitudinalReader.flatten(grid)
        XCTAssertEqual(table.rows.count, 1)
        let row = table.rows[0]
        XCTAssertEqual(row["Student Name"], "Abundis, Kataleah C.")
        XCTAssertEqual(row["Student ID"], "20212207")
        XCTAssertEqual(row["Academic Year"], "2024-25")
        XCTAssertEqual(row["Test Grade Level"], "01")
        XCTAssertEqual(row["Overall Performance Level"], "3L")
    }

    func testFlattenPrefersSummativeOverInitialForTheSameYear() throws {
        let grid = [
            Self.studentRow(name: "Acevedo, Valerie L.", id: "20180241"),
            Self.yearRow(testPurpose: "Initial", academicYear: "2018-19", gradeLevel: "KN"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2018-19", gradeLevel: "KN", overallLevel: "3H"),
        ]
        let table = try ELPACLongitudinalReader.flatten(grid)
        XCTAssertEqual(table.rows[0]["Test Purpose"], "Summative")
        XCTAssertEqual(table.rows[0]["Overall Performance Level"], "3H")
    }

    /// A more recent "Alternate ELPAC" administration never carries an
    /// Overall Performance Level in this report -- it must not shadow a real
    /// Summative result from an earlier year. ELPAC policy is that the last
    /// *obtained* level stays in effect until superseded.
    func testFlattenFallsBackToTheMostRecentYearThatActuallyProducedALevel() throws {
        let grid = [
            Self.studentRow(name: "Ramos, Abraham", id: "20171340"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2020-21", gradeLevel: "01", overallLevel: "1"),
            Self.yearRow(testPurpose: "Alternate", academicYear: "2021-22", gradeLevel: "02"),
            Self.yearRow(testPurpose: "Alternate", academicYear: "2025-26", gradeLevel: "06"),
        ]
        let table = try ELPACLongitudinalReader.flatten(grid)
        let row = table.rows[0]
        XCTAssertEqual(row["Academic Year"], "2020-21")
        XCTAssertEqual(row["Test Purpose"], "Summative")
        XCTAssertEqual(row["Test Grade Level"], "01")
        XCTAssertEqual(row["Overall Performance Level"], "1")
    }

    /// Unlike a student with no testing history at all, this one *was*
    /// tested -- just never scored (an Initial with no Summative since, or
    /// an Alternate-only history) -- so Academic Year/Test Purpose still
    /// reflect that most recent attempt; only the level itself is blank.
    func testFlattenShowsTheMostRecentAttemptWhenNoYearEverProducedALevel() throws {
        let grid = [
            Self.studentRow(name: "Aguilar, Emily E.", id: "20200371"),
            Self.yearRow(testPurpose: "Initial", academicYear: "2020-21", gradeLevel: "KN"),
        ]
        let table = try ELPACLongitudinalReader.flatten(grid)
        let row = table.rows[0]
        XCTAssertEqual(row["Academic Year"], "2020-21")
        XCTAssertEqual(row["Test Purpose"], "Initial")
        XCTAssertEqual(row["Overall Performance Level"], "")
    }

    func testFlattenHandlesMultipleStudentsAcrossARepeatedPageHeaderBlock() throws {
        let grid: [[String]] = [
            Self.studentRow(name: "Abundis, Kataleah C.", id: "20212207"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2024-25", gradeLevel: "KN", overallLevel: "3H"),
            titleRow,
            columnHeaderRow,
            Self.studentRow(name: "Acevedo, Sebastian A.", id: "20181477"),
            Self.yearRow(testPurpose: "Summative", academicYear: "2025-26", gradeLevel: "02", overallLevel: "2L"),
        ]
        let table = try ELPACLongitudinalReader.flatten(grid)
        XCTAssertEqual(table.rows.map { $0["Student ID"] }, ["20212207", "20181477"])
    }

    func testFlattenKeepsAStudentWithNoTestingHistoryYet() throws {
        let grid = [Self.studentRow(name: "Carrillo, Noah A.", id: "20260003", englishProficiency: "")]
        let table = try ELPACLongitudinalReader.flatten(grid)
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0]["Student ID"], "20260003")
        XCTAssertEqual(table.rows[0]["Academic Year"], "")
    }

    func testFlattenThrowsWhenNoStudentRowsAreFound() {
        XCTAssertThrowsError(try ELPACLongitudinalReader.flatten([titleRow, columnHeaderRow]))
    }

    // MARK: - Reading a real .xlsx file end to end

    func testReadsARealShapedXLSXFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/elpac_longitudinal_roster.xlsx")
        let table = try ELPACLongitudinalReader.read(contentsOf: url)
        XCTAssertEqual(table.headers, ELPACLongitudinalReader.outputHeaders)
        XCTAssertEqual(
            table.rows.map { $0["Student ID"] },
            ["20212207", "20180241", "20260003", "20220456"])
        XCTAssertEqual(table.rows[0]["Academic Year"], "2025-26")
        XCTAssertEqual(table.rows[1]["Test Purpose"], "Summative")
        XCTAssertEqual(table.rows[1]["Overall Performance Level"], "3H")
        XCTAssertEqual(table.rows[2]["Academic Year"], "")
        XCTAssertEqual(table.rows[3]["Overall Performance Level"], "4")
    }
}
