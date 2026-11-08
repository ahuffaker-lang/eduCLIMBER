import XCTest
@testable import EduClimberKit

final class HFWListConverterTests: XCTestCase {
    let converter = HFWListConverter()

    // MARK: - Fixture building

    func studentRow(
        name: String = "Azucena, Rene", id: String = "20220530", teacher: String = "Bednarik, Amanda N.",
        percent: String = "94.0%", correctQuestions: String = "a, an, the"
    ) -> [String: String] {
        [
            "Teacher": teacher, "Student Name": name, "Student ID": id, "Total Attempts": "1",
            "Last Assessed": "11/04/2026", "Number Correct": "47", "Number Incorrect": "3",
            "Number Answered": "50", "Number Possible": "50", "Percent Earned": percent,
            "Correct Questions": correctQuestions, "Assessment Name": "26-27 Kinder HFW List 1 & 2",
        ]
    }

    func makeTable(_ rows: [[String: String]]) -> Table {
        Table(headers: SkillAssessmentReader.outputHeaders, rows: rows)
    }

    func answers() -> [String: String] {
        [
            "assessment_group": "High Frequency Words",
            "assessment_name": "26-27 Kindergarten High Frequency Words List 1-2",
            "assessment_window": "Test 1",
            "grade": "K",
            "school_year": "2026-2027",
        ]
    }

    func convert(
        _ table: Table, answers: [String: String], using testConverter: HFWListConverter? = nil
    ) throws -> ConversionResult {
        let converter = testConverter ?? self.converter
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        return try Pipeline.convert(converter: converter, table: table, answers: answers, mapping: mapping)
    }

    // MARK: - Full row mapping

    func testFullRowMapping() throws {
        let table = makeTable([studentRow()])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first, [
            "Assessment Group": "High Frequency Words",
            "Assessment Name": "26-27 Kindergarten High Frequency Words List 1-2",
            "Assessment Window": "Test 1",
            "School Year": "2026-2027",
            "Student ID": "20220530",
            "Student First Name": "Rene",
            "Student Middle Initial": "",
            "Student Last Name": "Azucena",
            "Date of Birth": "",
            "Student Grade Level": "K",
            "Score": "94",
            "Score Detail 1 Words Correct": "a, an, the",
        ])
    }

    /// Unlike Letter ID/Letter Sounds, there's no Performance Band to upload
    /// -- Percent Earned becomes the Score directly, rounded to a whole number.
    func testPercentEarnedBecomesTheRoundedScore() throws {
        let table = makeTable([studentRow(percent: "2.0%")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Score"], "2")
    }

    func testNonNumericPercentIsFlagged() throws {
        let table = makeTable([studentRow(percent: "N/A")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("Percent Earned 'N/A' is not a number") },
            "\(result.errors.map(\.message))")
    }

    /// Messy spacing in the real export ("a , b  , c") is cleaned the same
    /// way the Letter ID/Letter Sounds converter already cleans it.
    func testCorrectQuestionsSpacingIsCleaned() throws {
        let table = makeTable([studentRow(correctQuestions: "a ,  b ,c")])
        let result = try convert(table, answers: answers())
        XCTAssertEqual(result.rows.first?["Score Detail 1 Words Correct"], "a, b, c")
    }

    func testBlankCorrectQuestionsConvertsCleanly() throws {
        let table = makeTable([studentRow(correctQuestions: "")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Score Detail 1 Words Correct"], "")
    }

    // MARK: - Validation

    func testBlankStudentIDIsFlagged() throws {
        let table = makeTable([studentRow(id: "")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("Student ID is blank") },
            "\(result.errors.map(\.message))")
    }

    func testDuplicateStudentIDIsFlagged() throws {
        let table = makeTable([
            studentRow(name: "Azucena, Rene", id: "20220530"),
            studentRow(name: "Garcia, Emmitt", id: "20220530"),
        ])
        let result = try convert(table, answers: answers())
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("appears more than once in this file") },
            "\(result.errors.map(\.message))")
    }

    func testStudentNameNotInLastFirstFormatIsFlagged() throws {
        let table = makeTable([studentRow(name: "Rene Azucena")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("is not in 'Last, First' format") },
            "\(result.errors.map(\.message))")
    }

    /// Same Name Fixes table Letter ID/Letter Sounds already uses -- this
    /// export comes from the same Skill Assessment Student List format, so a
    /// student missing a first name there is missing it here too.
    func testNameFixesSuppliesTheFirstNameWhenTheExportIsMissingIt() throws {
        let table = makeTable([studentRow(name: "Copado Cuevas, ", id: "20222971")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Maximiliano")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Copado Cuevas")
    }

    func testMissingFirstNameWithoutAFixIsFlagged() throws {
        let table = makeTable([studentRow(name: "Nobody, ", id: "99999999")])
        let result = try convert(table, answers: answers())
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("isn't in the Name Fixes table") },
            "\(result.errors.map(\.message))")
    }

    // MARK: - Student Roster fallback

    func testStudentRosterFirstNameTakesPriorityOverTheHardcodedNameFixesTable() throws {
        let rosterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("student_roster.csv")
        try StudentRosterStore.save(
            [StudentRosterEntry(studentID: "20222971", firstName: "FromRoster")], to: rosterURL)
        let converterWithRoster = HFWListConverter(rosterStoreURL: rosterURL)

        let table = makeTable([studentRow(name: "Copado Cuevas, ", id: "20222971")])
        let result = try convert(table, answers: answers(), using: converterWithRoster)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "FromRoster")
    }

    // MARK: - Batch-wide prompts

    func testAssessmentFieldsComeFromPromptsNotTheFile() throws {
        let table = makeTable([studentRow()])
        var customAnswers = answers()
        customAnswers["assessment_group"] = "Custom Group"
        customAnswers["assessment_name"] = "Custom Name"
        customAnswers["grade"] = "1"
        let result = try convert(table, answers: customAnswers)
        XCTAssertEqual(result.rows.first?["Assessment Group"], "Custom Group")
        XCTAssertEqual(result.rows.first?["Assessment Name"], "Custom Name")
        XCTAssertEqual(result.rows.first?["Student Grade Level"], "1")
    }

    func testAssessmentWindowChoices() {
        let prompt = converter.prompts.first { $0.key == "assessment_window" }!
        XCTAssertEqual(prompt.choices, ["Test 1", "Test 2", "Test 3"])
    }

    func testSchoolYearPromptCarriesTheComputedDefault() {
        let prompt = converter.prompts.first { $0.key == "school_year" }!
        XCTAssertEqual(prompt.defaultValue, EurekaMathConverter.currentSchoolYear())
    }

    // MARK: - Output shape

    func testOutputColumnOrder() {
        XCTAssertEqual(converter.outputColumns, [
            "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
            "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
            "Date of Birth", "Student Grade Level", "Score", "Score Detail 1 Words Correct",
        ])
    }
}
