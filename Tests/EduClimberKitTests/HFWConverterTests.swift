import XCTest
@testable import EduClimberKit

final class HFWConverterTests: XCTestCase {
    let converter = HFWConverter()
    let header = "Assessment,Student Id,SSID,First Name,Last Name,Birth Date,Grade Level,"
        + "Date Taken,Number Correct,Number Possible,% Correct,Performance Band,"
        + "Performance Band Level\n"

    func writeCSV(_ body: String, name: String = "source.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try (header + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    let sampleRow =
        "25-26 Gr 1 HFW Admin #1,2021xxx,78167xxxx,Joe,Smith,01/30/2019,2nd Grade,"
        + "10/28/2025,35,177,19.77%,Below Basic,2\n"

    // MARK: - Parsing the Assessment column

    func testParseAssessmentExtractsYearAndAdministration() {
        let parsed = HFWConverter.parseAssessment("25-26 Gr 1 HFW Admin #1")
        XCTAssertEqual(parsed?.schoolYear, "2025-2026")
        XCTAssertEqual(parsed?.window, "Administration 1")
    }

    func testParseAssessmentHandlesAllThreeAdministrations() {
        XCTAssertEqual(
            HFWConverter.parseAssessment("25-26 Gr 1 HFW Admin #2")?.window, "Administration 2")
        XCTAssertEqual(
            HFWConverter.parseAssessment("25-26 Gr 1 HFW Admin #3")?.window, "Administration 3")
    }

    func testParseAssessmentIsNilForUnrecognizedText() {
        XCTAssertNil(HFWConverter.parseAssessment(""))
        XCTAssertNil(HFWConverter.parseAssessment("Some other assessment"))
        XCTAssertNil(HFWConverter.parseAssessment("25-26 Gr 1 HFW"))
    }

    // MARK: - Grade normalization

    func testNormalizeGradeHandlesOrdinalsAndKindergarten() {
        XCTAssertEqual(HFWConverter.normalizeGrade("2nd Grade"), "2")
        XCTAssertEqual(HFWConverter.normalizeGrade("Grade 5"), "5")
        XCTAssertEqual(HFWConverter.normalizeGrade("K"), "K")
        XCTAssertEqual(HFWConverter.normalizeGrade("Kindergarten"), "K")
        XCTAssertNil(HFWConverter.normalizeGrade(""))
        XCTAssertNil(HFWConverter.normalizeGrade("Ungraded"))
    }

    // MARK: - Full row mapping

    func testFullRowMapping() throws {
        let url = try writeCSV(sampleRow)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first, [
            "Assessment Group": "High Frequency Words",
            "Assessment Name": "HFW",
            "Assessment Window": "Administration 1",
            "School Year": "2025-2026",
            "Student ID": "2021xxx",
            "Student First Name": "Joe",
            "Student Middle Initial": "",
            "Student Last Name": "Smith",
            "Date of Birth": "",
            "Student Grade Level": "2",
            "Score Detail 2 Performance Band": "Below Basic",
            "Score Detail 1 Percent Correct": "19.77%",
            "Score": "2",
        ])
    }

    /// The three administrations mix in one file; each row carries its own
    /// window and year rather than the user picking one for the whole batch.
    func testDifferentAdministrationsInTheSameFileGetDifferentWindows() throws {
        let url = try writeCSV(
            "25-26 Gr 1 HFW Admin #1,1,1,Joe,Smith,,1st Grade,,10,20,50%,Basic,2\n"
            + "25-26 Gr 1 HFW Admin #2,2,2,Ann,Lee,,1st Grade,,15,20,75%,Proficient,3\n"
            + "25-26 Gr 1 HFW Admin #3,3,3,Sam,Ray,,1st Grade,,20,20,100%,Advanced,4\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.rows.map { $0["Assessment Window"] }, [
            "Administration 1", "Administration 2", "Administration 3",
        ])
    }

    func testUsesStudentIdColumnNotSSID() throws {
        let url = try writeCSV(sampleRow)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        XCTAssertEqual(result.rows.first?["Student ID"], "2021xxx", "not the SSID column")
    }

    // MARK: - Validation

    func testBlankRequiredFieldsAreFlagged() throws {
        let url = try writeCSV(",,,,,,,,,,,,\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        let messages = result.errors.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Student Id is blank") })
        XCTAssertTrue(messages.contains { $0.contains("First Name is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Last Name is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Grade Level is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Assessment is blank") })
        XCTAssertTrue(messages.contains { $0.contains("% Correct is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Performance Band is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Performance Band Level is blank") })
    }

    func testUnrecognizedAssessmentTextIsFlagged() throws {
        let url = try writeCSV(
            "Some other test,1,1,Joe,Smith,,2nd Grade,,10,20,50%,Basic,2\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        XCTAssertTrue(result.errors.contains { $0.message.contains("not in the expected") })
    }

    func testNonNumericPerformanceBandLevelIsFlagged() throws {
        let url = try writeCSV(
            "25-26 Gr 1 HFW Admin #1,1,1,Joe,Smith,,2nd Grade,,10,20,50%,Basic,N/A\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        XCTAssertTrue(result.errors.contains { $0.message.contains("is not a number") })
    }

    func testUnrecognizedGradeIsFlagged() throws {
        let url = try writeCSV(
            "25-26 Gr 1 HFW Admin #1,1,1,Joe,Smith,,Ungraded,,10,20,50%,Basic,2\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: [:])
        XCTAssertTrue(result.errors.contains { $0.message.contains("is not recognized") })
    }

    // MARK: - Output shape

    func testOutputColumnOrder() {
        XCTAssertEqual(converter.outputColumns, [
            "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
            "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
            "Date of Birth", "Student Grade Level", "Score Detail 2 Performance Band",
            "Score Detail 1 Percent Correct", "Score",
        ])
    }

    func testNoPromptsAreNeeded() {
        XCTAssertTrue(converter.prompts.isEmpty)
        XCTAssertEqual(Pipeline.validateAnswers(converter: converter, answers: [:]), [])
    }
}
