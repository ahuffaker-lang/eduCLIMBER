import XCTest
@testable import EduClimberKit

final class TagUploadConverterTests: XCTestCase {
    let converter = TagUploadConverter()

    func writeCSV(_ header: String, _ body: String, name: String = "tags.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try (header + "\n" + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func answers(
        year: String = "2026-2027", tagName: String = "Special Education", tagFlag: String? = "Y"
    ) -> [String: String] {
        var values = ["school_year": year, "tag_name": tagName]
        if let tagFlag { values["tag_flag"] = tagFlag }
        return values
    }

    // MARK: - Full row mapping

    func testFullRowMapping() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,Ethan,Garcia")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first, [
            "Student ID": "20212318",
            "Student First Name": "Ethan",
            "Student Last Name": "Garcia",
            "School Year": "2026-2027",
            "Tag Name": "Special Education",
            "Tag Flag": "Y",
        ])
    }

    /// The source file is never the same shape twice -- today's happens to
    /// use plain "ID"/"First Name"/"Last Name" instead of the canonical
    /// labels, and the usual alias matching has to find them anyway.
    func testDifferentlyNamedColumnsStillMatch() throws {
        let url = try writeCSV(
            "ID,First Name,Last Name,Grade",
            "20212318,Ethan,Garcia,5")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student ID"], "20212318")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
    }

    // MARK: - Tag Flag is optional

    func testTagFlagLeftBlankConvertsCleanly() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,Ethan,Garcia")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers(tagFlag: ""))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Tag Flag"], "")
    }

    func testTagFlagPromptAcceptsAMissingAnswerEntirely() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,Ethan,Garcia")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers(tagFlag: nil))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Tag Flag"], "")
    }

    func testTagFlagPromptValidatesAsOptional() {
        let prompt = converter.prompts.first { $0.key == "tag_flag" }!
        XCTAssertFalse(prompt.isRequired)
        XCTAssertNil(prompt.validate(""))
        XCTAssertNil(prompt.validate(nil))
        XCTAssertNil(prompt.validate("Y"))
    }

    func testTagNamePromptIsStillRequired() {
        let prompt = converter.prompts.first { $0.key == "tag_name" }!
        XCTAssertTrue(prompt.isRequired)
        XCTAssertNotNil(prompt.validate(""))
    }

    // MARK: - Validation

    func testBlankStudentIDIsFlagged() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            ",Ethan,Garcia")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.errors.contains { $0.message.contains("Student ID is blank") })
    }

    func testBlankFirstNameIsFlagged() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,,Garcia")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("Student First Name is blank") })
    }

    func testBlankLastNameIsFlagged() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,Ethan,")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("Student Last Name is blank") })
    }

    func testMissingRequiredColumnIsReported() throws {
        let url = try writeCSV(
            "Student ID,Student First Name",
            "20212318,Ethan")
        XCTAssertThrowsError(
            try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("Student Last Name"), "\(error)")
        }
    }

    func testEmptySourceFileThrows() throws {
        let url = try writeCSV("Student ID,Student First Name,Student Last Name", "")
        XCTAssertThrowsError(
            try Pipeline.convertFile(converter: converter, url: url, answers: answers()))
    }

    // MARK: - School Year prompt defaults to the current academic year

    func testSchoolYearPromptCarriesTheComputedDefault() {
        let prompt = converter.prompts.first { $0.key == "school_year" }!
        XCTAssertEqual(prompt.defaultValue, EurekaMathConverter.currentSchoolYear())
    }

    // MARK: - Output shape

    func testOutputColumnOrder() {
        XCTAssertEqual(converter.outputColumns, [
            "Student ID", "Student First Name", "Student Last Name",
            "School Year", "Tag Name", "Tag Flag",
        ])
    }

    func testDefaultFileNameIncludesTagNameAndYear() {
        let name = converter.defaultOutputName(answers: answers())
        XCTAssertEqual(name, "SpecialEducation_2026-2027_tag_upload.csv")
    }
}
