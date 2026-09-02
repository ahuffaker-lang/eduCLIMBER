import XCTest
@testable import EduClimberKit

final class RunningRecordsTests: XCTestCase {
    let converter = RunningRecordsConverter()
    let answers = ["assessment_window": "Trimester 2", "school_year": "2026-2027"]
    let header = "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"

    func writeCSV(_ body: String, header: String? = nil, name: String = "source.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try ((header ?? self.header) + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Lookup table

    func testLookupTableMatchesSpec() {
        XCTAssertEqual(ReadingLevels.ordered.count, 29)
        XCTAssertEqual(ReadingLevels.score(for: "Below A"), 1)
        XCTAssertEqual(ReadingLevels.score(for: "A"), 2)
        XCTAssertEqual(ReadingLevels.score(for: "Z"), 27)
        XCTAssertEqual(ReadingLevels.score(for: "Z+"), 28)
        XCTAssertEqual(ReadingLevels.score(for: "MAX"), 29)
        XCTAssertEqual(ReadingLevels.score(for: "below a"), 1)  // case-insensitive
        XCTAssertNil(ReadingLevels.score(for: "QQ"))
    }

    /// The embedded table and the reference Data_Table.csv must not drift apart.
    func testEmbeddedTableMatchesDataTableCSV() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EduClimberKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let csv = repoRoot.appendingPathComponent("Resources/Data_Table.csv")
        let rows = CSVReader.parse(try String(contentsOf: csv, encoding: .utf8))
        let pairs = rows.dropFirst()
            .filter { $0.count >= 2 && !$0[0].isEmpty }
            .map { (level: $0[1], score: Int($0[0]) ?? -1) }
        XCTAssertEqual(pairs.count, ReadingLevels.ordered.count)
        for (fromFile, embedded) in zip(pairs, ReadingLevels.ordered) {
            XCTAssertEqual(fromFile.level, embedded.level)
            XCTAssertEqual(fromFile.score, embedded.score)
        }
    }

    // MARK: - Mapping

    func testOutputColumnOrder() {
        XCTAssertEqual(converter.outputColumns, [
            "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
            "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
            "Date of Birth", "Student Grade Level", "Score Detail 2", "Reading Level",
            "Score Detail 1", "Proficiency Level", "Score",
        ])
    }

    func testSplitStudentName() {
        XCTAssertEqual(RunningRecordsConverter.splitStudentName("Gomez, Maria").first, "Maria")
        XCTAssertEqual(RunningRecordsConverter.splitStudentName("Gomez, Maria").last, "Gomez")
        XCTAssertEqual(RunningRecordsConverter.splitStudentName("  Smith ,  John  ").first, "John")
        XCTAssertEqual(RunningRecordsConverter.splitStudentName("  Smith ,  John  ").last, "Smith")
        XCTAssertEqual(
            RunningRecordsConverter.splitStudentName("Van Dyke, Anna Lee").first, "Anna Lee")
        XCTAssertEqual(RunningRecordsConverter.splitStudentName("NoComma").first, "")
    }

    func testFullRowMapping() throws {
        let url = try writeCSV("\"Gomez, Maria\",123456,3,Below A,Far Below Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.rows.first, [
            "Assessment Group": "Running Records",
            "Assessment Name": "Independent Reading Level",
            "Assessment Window": "Trimester 2",
            "School Year": "2026-2027",
            "Student ID": "123456",
            "Student First Name": "Maria",
            "Student Middle Initial": "",
            "Student Last Name": "Gomez",
            "Date of Birth": "",
            "Student Grade Level": "3",
            "Score Detail 2": "Below A",
            "Reading Level": "Below A",
            "Score Detail 1": "Far Below Standard",
            "Proficiency Level": "Far Below Standard",
            "Score": "1",
        ])
    }

    func testDuplicateColumnsStayInSync() throws {
        let url = try writeCSV("\"Lee, Sam\",1,K,M,At Standard\n")
        let row = try XCTUnwrap(
            Pipeline.convertFile(converter: converter, url: url, answers: answers).rows.first)
        XCTAssertEqual(row["Score Detail 2"], row["Reading Level"])
        XCTAssertEqual(row["Score Detail 1"], row["Proficiency Level"])
        XCTAssertEqual(row["Score"], "14")
    }

    func testHeadersMatchLooselyAndCaseInsensitively() throws {
        let loose = "  STUDENT ,student_id,grade level,Reading Level A-Z,proficiency level\n"
        let url = try writeCSV("\"Gomez, Maria\",7,2,C,At Standard\n", header: loose)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertEqual(result.rows.first?["Student First Name"], "Maria")
        XCTAssertEqual(result.rows.first?["Score"], "4")
    }

    func testGradeKPassesThrough() throws {
        let url = try writeCSV("\"Ng, Ada\",9,K,A,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertEqual(result.rows.first?["Student Grade Level"], "K")
    }

    // MARK: - Validation

    func testUnknownReadingLevelIsFlagged() throws {
        let url = try writeCSV("\"Ng, Ada\",9,K,A,At Standard\n\"Ray, Jo\",10,1,QQ,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.rowNumber, 3)
        XCTAssertTrue(
            result.errors[0].message.contains("not in the reading level table"),
            result.errors[0].message)
        XCTAssertFalse(result.isClean)
    }

    func testBlankReadingLevelAndMissingIDAreFlagged() throws {
        let url = try writeCSV("\"Ng, Ada\",,K,A,At Standard\n\"Ray, Jo\",10,1,,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        let messages = result.errors.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Student ID is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Reading Level (A-Z) is blank") })
    }

    func testUnparseableStudentNameIsFlagged() throws {
        let url = try writeCSV("Maria Gomez,9,1,C,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertTrue(
            result.errors[0].message.contains("is not in 'Last, First' format"),
            result.errors[0].message)
    }

    func testEmptyFileThrows() throws {
        let url = try writeCSV("", header: "")
        XCTAssertThrowsError(try Pipeline.loadSource(at: url))
    }

    func testBlankRowsAreSkipped() throws {
        let url = try writeCSV(
            "\"Ng, Ada\",9,K,A,At Standard\n,,,,\n\"Ray, Jo\",10,1,B,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.rows.count, 2)
    }

    /// A skipped blank row must not shift the row numbers reported for the rows
    /// after it -- they have to match what the user sees in the spreadsheet.
    func testBlankRowsDoNotShiftReportedRowNumbers() throws {
        let url = try writeCSV(
            "\"Ng, Ada\",9,K,A,At Standard\n,,,,\n\"Ray, Jo\",10,1,QQ,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.rowNumber, 4)
    }

    func testSchoolYearValidation() {
        for year in ["2026-2027", "2025-2026"] {
            let problems = Pipeline.validateAnswers(
                converter: converter,
                answers: ["assessment_window": "Trimester 1", "school_year": year])
            XCTAssertEqual(problems, [], year)
        }
        for year in ["2026 - 2027", "26-27", "2026/2027", "", "2026-20277"] {
            let problems = Pipeline.validateAnswers(
                converter: converter,
                answers: ["assessment_window": "Trimester 1", "school_year": year])
            XCTAssertFalse(problems.isEmpty, year)
        }
    }

    func testInvalidAssessmentWindow() {
        let problems = Pipeline.validateAnswers(
            converter: converter,
            answers: ["assessment_window": "Trimester 4", "school_year": "2026-2027"])
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("Assessment Window"))
    }

    // MARK: - Output

    func testWrittenCSVHasExactColumnsAndNoBOM() throws {
        let url = try writeCSV("\"Ng, Ada\",9,K,A,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        let out = url.deletingLastPathComponent().appendingPathComponent("out.csv")
        try Pipeline.save(result: result, to: out)

        let data = try Data(contentsOf: out)
        XCTAssertFalse(data.starts(with: [0xEF, 0xBB, 0xBF]), "the upload must not start with a BOM")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let rows = CSVReader.parse(text)
        XCTAssertEqual(rows[0], converter.outputColumns)
        XCTAssertEqual(rows[1].last, "2")
    }

    func testFieldsWithCommasAreQuoted() {
        let text = CSVWriter.text(
            columns: ["A", "B"], rows: [["A": "Gomez, Maria", "B": "say \"hi\""]])
        XCTAssertTrue(text.contains("\"Gomez, Maria\""), text)
        XCTAssertTrue(text.contains("\"say \"\"hi\"\"\""), text)
    }

    func testDefaultOutputName() {
        XCTAssertEqual(
            converter.defaultOutputName(answers: answers),
            "Running_Records_Trimester2_2026-2027_educlimber.csv")
    }
}

// MARK: - Reviewing and skipping suspect rows

extension RunningRecordsTests {
    /// A file with problems still converts its good rows; the bad ones are
    /// reported so the app can offer to skip them.
    func testGoodRowsSurviveAlongsideProblemRows() throws {
        let url = try writeCSV(
            """
            "Ng, Ada",9,K,A,At Standard
            "Ray, Jo",10,1,QQ,At Standard
            "Lee, Sam",11,2,C,At Standard
            ,,,,\u{20}
            "Doe, Pat",,3,D,At Standard
            """ + "\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)

        XCTAssertEqual(result.rows.count, 2, "Ada and Sam convert")
        XCTAssertTrue(result.hasUsableRows)
        XCTAssertEqual(result.skippedRowCount, 2, "Jo and Pat are skipped")
        XCTAssertEqual(result.issues.map(\.rowNumber), [3, 6])
    }

    /// One row failing for two reasons is listed once, with both reasons.
    func testAllProblemsForARowAreGroupedTogether() throws {
        let url = try writeCSV("\"Ray, Jo\",,1,QQ,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)

        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.issues.count, 1)
        let issue = try XCTUnwrap(result.issues.first)
        XCTAssertEqual(issue.rowNumber, 2)
        XCTAssertEqual(issue.problems.count, 2)
        XCTAssertTrue(issue.summary.contains("Student ID is blank"), issue.summary)
        XCTAssertTrue(issue.summary.contains("reading level table"), issue.summary)
    }

    func testNothingUsableIsReportedAsSuch() throws {
        let url = try writeCSV("\"Ray, Jo\",10,1,QQ,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertFalse(result.hasUsableRows)
        XCTAssertEqual(result.skippedRowCount, 1)
    }

    func testIssuesReportIsCopyableText() throws {
        let url = try writeCSV("\"Ng, Ada\",9,K,A,At\n\"Ray, Jo\",10,1,QQ,At Standard\n")
        let report = try Pipeline
            .convertFile(converter: converter, url: url, answers: answers)
            .issuesReport()
        XCTAssertTrue(report.hasPrefix("Row 3:"), report)
        XCTAssertTrue(report.contains("Ray, Jo"), report)
    }

    /// Skipping rows must not disturb the exported file: it holds exactly the
    /// good rows, in order, with the full column set.
    func testExportAfterSkippingHoldsOnlyGoodRows() throws {
        let url = try writeCSV(
            "\"Ng, Ada\",9,K,A,At Standard\n\"Ray, Jo\",10,1,QQ,At Standard\n"
            + "\"Lee, Sam\",11,2,C,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        let out = url.deletingLastPathComponent().appendingPathComponent("skipped.csv")
        try Pipeline.save(result: result, to: out)

        let rows = CSVReader.parse(try String(contentsOf: out, encoding: .utf8))
        XCTAssertEqual(rows[0], converter.outputColumns)
        XCTAssertEqual(rows.count, 3, "header plus the two good rows")
        XCTAssertEqual(rows[1][7], "Ng")
        XCTAssertEqual(rows[2][7], "Lee")
    }
}
