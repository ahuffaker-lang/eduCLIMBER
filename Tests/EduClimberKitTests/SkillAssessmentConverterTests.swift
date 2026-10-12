import XCTest
@testable import EduClimberKit

final class SkillAssessmentConverterTests: XCTestCase {
    let converter = SkillAssessmentConverter()

    // MARK: - Fixture building

    func studentRow(
        name: String = "Flores, Alexander", id: String = "20221371", teacher: String = "Alvarado, Maria",
        attempts: String = "1", correct: String = "26", incorrect: String = "0", answered: String = "26",
        possible: String = "26", percent: String = "100.0%", correctQuestions: String = "a, b, c",
        assessmentName: String = "26-27 Letter Sounds"
    ) -> [String: String] {
        [
            "Teacher": teacher, "Student Name": name, "Student ID": id, "Total Attempts": attempts,
            "Last Assessed": "10/05/2026", "Number Correct": correct, "Number Incorrect": incorrect,
            "Number Answered": answered, "Number Possible": possible, "Percent Earned": percent,
            "Correct Questions": correctQuestions, "Assessment Name": assessmentName,
        ]
    }

    func makeTable(_ rows: [[String: String]]) -> Table {
        Table(headers: SkillAssessmentReader.outputHeaders, rows: rows)
    }

    func writeAeriesCSV(
        _ rows: [(id: String, grade: String, school: String)],
        headerOrder: String = "Student ID,Grade,School"
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("aeries.csv")
        let columns = headerOrder.components(separatedBy: ",")
        var text = headerOrder + "\n"
        for row in rows {
            let values: [String: String] = ["Student ID": row.id, "Grade": row.grade, "School": row.school]
            text += columns.map { values[$0] ?? "" }.joined(separator: ",") + "\n"
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func answers(aeriesPath: String) -> [String: String] {
        [
            "assessment_group": "Foundational Skills",
            "assessment_window": "Test 1",
            "school_year": "2026-2027",
            "aeries_file": aeriesPath,
        ]
    }

    func convert(_ table: Table, answers: [String: String]) throws -> ConversionResult {
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        return try Pipeline.convert(converter: converter, table: table, answers: answers, mapping: mapping)
    }

    // MARK: - Full row mapping

    func testFullRowMapping() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first, [
            "Assessment Group": "Foundational Skills",
            "Assessment Name": "26-27 Letter Sounds",
            "Assessment Window": "Test 1",
            "School Year": "2026-2027",
            "Student ID": "20221371",
            "Student First Name": "Alexander",
            "Student Middle Initial": "",
            "Student Last Name": "Flores",
            "Date of Birth": "",
            "Student Grade Level": "K",
            "Score": "100",
            "Score Detail 1 Number Correct": "26",
            "Score Detail 2 Total Attempts": "1",
            "Score Detail 3 Correct Letters": "a, b, c",
        ])
    }

    func testAssessmentNameIsDetectedFromTheDataNotAskedFor() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(assessmentName: "26-27 Letter Identification")])
        let noAssessmentNameAnswer = answers(aeriesPath: aeries.path)
        XCTAssertNil(noAssessmentNameAnswer["assessment_name"], "nothing should need to ask for it")
        let result = try convert(table, answers: noAssessmentNameAnswer)
        XCTAssertEqual(result.rows.first?["Assessment Name"], "26-27 Letter Identification")
    }

    func testThrowsWhenAssessmentNameIsBlank() {
        let table = makeTable([studentRow(assessmentName: "")])
        XCTAssertThrowsError(try convert(table, answers: answers(aeriesPath: "/nonexistent")))
    }

    // MARK: - Name Fixes

    func testNameFixesSuppliesTheFirstNameWhenTheExportIsMissingIt() throws {
        let aeries = try writeAeriesCSV([(id: "20222971", grade: "0", school: "667")])
        let table = makeTable([studentRow(name: "Copado Cuevas, ", id: "20222971")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Maximiliano")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Copado Cuevas")
    }

    func testMissingFirstNameWithoutAFixIsFlagged() throws {
        let aeries = try writeAeriesCSV([(id: "99999999", grade: "0", school: "667")])
        let table = makeTable([studentRow(name: "Nobody, ", id: "99999999")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("isn't in the Name Fixes table") },
            "\(result.errors.map(\.message))")
    }

    // MARK: - The Aeries join

    func testStudentNotInAeriesFileIsFlagged() throws {
        let aeries = try writeAeriesCSV([(id: "00000000", grade: "0", school: "667")])
        let table = makeTable([studentRow(id: "20221371")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("was not found in the Aeries") },
            "\(result.errors.map(\.message))")
    }

    /// Positive codes map to themselves with no upper bound ("and so on" per
    /// the district's own spec), so only a code outside that pattern -- not a
    /// large grade number -- is actually unrecognized.
    func testUnrecognizedGradeCodeIsFlaggedAsBlocking() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "-2", school: "667")])
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("Grade code '-2'") },
            "\(result.errors.map(\.message))")
    }

    func testALargePositiveGradeCodeIsNotTreatedAsUnrecognized() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "12", school: "667")])
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student Grade Level"], "12")
    }

    func testUnrecognizedSchoolCodeIsANoticeNotAnError() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "999")])
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean, "an unrecognized school code should not block the row")
        XCTAssertTrue(
            result.notices.contains { $0.message.contains("School code '999'") },
            "\(result.notices.map(\.message))")
    }

    func testTKGradeIsANoticeNotAnError() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "-1", school: "667")])
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.rows.first?["Student Grade Level"], "TK")
        XCTAssertTrue(result.notices.contains { $0.message.contains("coded TK") })
    }

    func testAeriesColumnOrderDoesNotMatter() throws {
        let aeries = try writeAeriesCSV(
            [(id: "20221371", grade: "0", school: "667")], headerOrder: "Grade,School,Student ID")
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student Grade Level"], "K")
    }

    /// Pipeline.convert() rejects a blank "aeries_file" answer as a required
    /// prompt before SkillAssessmentConverter.convert() itself ever runs --
    /// the same path every other required prompt here goes through.
    func testThrowsWhenAeriesFileAnswerIsMissing() {
        let table = makeTable([studentRow()])
        var noFile = answers(aeriesPath: "")
        noFile.removeValue(forKey: "aeries_file")
        XCTAssertThrowsError(try convert(table, answers: noFile)) { error in
            XCTAssertTrue(
                (error as? ConverterError)?.message.contains("Aeries Grade/School File is required")
                    == true,
                (error as? ConverterError)?.message ?? "no message")
        }
    }

    func testThrowsWhenAeriesFileCannotBeRead() {
        let table = makeTable([studentRow()])
        XCTAssertThrowsError(
            try convert(table, answers: answers(aeriesPath: "/nonexistent/aeries.csv"))
        ) { error in
            XCTAssertTrue(
                (error as? ConverterError)?.message.contains("Could not read the Aeries") == true)
        }
    }

    // MARK: - Duplicate Student ID

    func testDuplicateStudentIDIsFlagged() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(), studentRow()])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("appears more than once") },
            "\(result.errors.map(\.message))")
    }

    // MARK: - Score / Percent Earned

    func testPercentEarnedRoundsHalfUp() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(percent: "50.5%")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertEqual(result.rows.first?["Score"], "51")
    }

    func testUnparseablePercentEarnedIsFlagged() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(percent: "N/A")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.errors.contains { $0.message.contains("Percent Earned 'N/A'") })
    }

    func testZeroAnsweredIsANoticeNotAnError() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(correct: "0", answered: "0", percent: "0.0%", correctQuestions: "")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertTrue(result.notices.contains { $0.message.contains("0 questions were answered") })
    }

    func testScoreOfZeroWithNonzeroAnsweredIsANoticeNotAnError() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(correct: "0", answered: "26", percent: "0.0%", correctQuestions: "")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.isClean)
        XCTAssertTrue(result.notices.contains { $0.message.contains("Score is 0") })
    }

    // MARK: - Correct Questions cleanup

    func testCorrectQuestionsSpacingIsCleaned() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(correctQuestions: "a , b , c  , d")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertEqual(result.rows.first?["Score Detail 3 Correct Letters"], "a, b, c, d")
    }

    // MARK: - Validation

    func testBlankRequiredFieldsAreFlagged() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(
            name: "", id: "", attempts: "", correct: "", answered: "", percent: "")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        let messages = result.errors.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Student ID is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Student Name is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Total Attempts '' is not a number") })
        XCTAssertTrue(messages.contains { $0.contains("Number Correct '' is not a number") })
        XCTAssertTrue(messages.contains { $0.contains("Percent Earned '' is not a number") })
    }

    func testUnparseableStudentNameIsFlagged() throws {
        let aeries = try writeAeriesCSV([(id: "20221371", grade: "0", school: "667")])
        let table = makeTable([studentRow(name: "Alexander Flores")])
        let result = try convert(table, answers: answers(aeriesPath: aeries.path))
        XCTAssertTrue(result.errors.contains { $0.message.contains("is not in 'Last, First' format") })
    }

    // MARK: - Output shape

    func testOutputColumnOrder() {
        XCTAssertEqual(converter.outputColumns, [
            "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
            "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
            "Date of Birth", "Student Grade Level", "Score",
            "Score Detail 1 Number Correct", "Score Detail 2 Total Attempts",
            "Score Detail 3 Correct Letters",
        ])
    }
}
