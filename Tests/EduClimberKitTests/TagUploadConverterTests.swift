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

    func testMissingStudentIDColumnIsReported() throws {
        let url = try writeCSV(
            "Student First Name,Student Last Name",
            "Ethan,Garcia")
        XCTAssertThrowsError(
            try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Student ID"), "\(error)")
        }
    }

    // MARK: - The name can arrive combined or split

    /// An Aeries "Print Query to Excel" export, for one, has a single
    /// "Student Name" column ("Last, First") rather than separate first and
    /// last name columns -- the same ambiguity Running Records already
    /// handles, so Tag Upload has to handle it too.
    func testCombinedStudentNameColumnIsSplit() throws {
        let url = try writeCSV(
            "Student ID,Student Name",
            "20212318,\"Garcia, Ethan\"")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
    }

    /// Split columns win when a file somehow has both -- no parsing needed
    /// when the source already did the work.
    func testSplitColumnsAreUsedOverACombinedColumnWhenBothArePresent() throws {
        let url = try writeCSV(
            "Student ID,Student Name,Student First Name,Student Last Name",
            "20212318,\"Wrong, Name\",Ethan,Garcia")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
    }

    func testCombinedNameNotInLastFirstFormatIsFlagged() throws {
        let url = try writeCSV(
            "Student ID,Student Name",
            "20212318,Ethan Garcia")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("is not in 'Last, First' format") })
    }

    func testNeitherCombinedNorSplitNameThrows() throws {
        let url = try writeCSV("Student ID", "20212318")
        XCTAssertThrowsError(
            try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("needs the student name"), "\(error)")
        }
    }

    // MARK: - Student Roster fallback

    func testBlankNameIsFilledFromTheStudentRoster() throws {
        let rosterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("student_roster.csv")
        try StudentRosterStore.save(
            [StudentRosterEntry(studentID: "20212318", firstName: "Ethan", lastName: "Garcia")],
            to: rosterURL)
        let converterWithRoster = TagUploadConverter(rosterStoreURL: rosterURL)

        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,,")
        let result = try Pipeline.convertFile(converter: converterWithRoster, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
    }

    // MARK: - Duplicate Student IDs are removed

    /// A query listing one row per enrollment segment can repeat a student;
    /// a tag upload should only tag them once.
    func testDuplicateStudentIDRowsAreSkipped() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,Ethan,Garcia\n20212319,Ava,Smith\n20212318,Ethan,Garcia")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows.map { $0["Student ID"] }, ["20212318", "20212319"])
        // The duplicate is the third data row -- row 4, counting the header.
        XCTAssertEqual(result.notices.count, 1)
        XCTAssertEqual(result.notices.first?.rowNumber, 4)
        XCTAssertTrue(
            result.notices.first?.message.contains("20212318") ?? false,
            "\(result.notices)")
    }

    /// The first row for a repeated ID wins, whatever a later copy says.
    func testFirstOccurrenceWinsWhenDuplicateRowsDisagree() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            "20212318,Ethan,Garcia\n20212318,Mistyped,Name")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
    }

    /// A blank Student ID isn't a real key -- two blank-ID rows are two
    /// separate problems, not duplicates of each other.
    func testBlankStudentIDRowsAreNotTreatedAsDuplicates() throws {
        let url = try writeCSV(
            "Student ID,Student First Name,Student Last Name",
            ",Ethan,Garcia\n,Ava,Smith")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(
            result.errors.filter { $0.message.contains("Student ID is blank") }.count, 2)
        XCTAssertFalse(result.notices.contains { $0.message.contains("duplicate") })
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

    func testDefaultFileNameFollowsTheStandardConvention() {
        let name = converter.defaultOutputName(answers: answers())
        XCTAssertTrue(name.hasPrefix("eduCLIMBER_Upload_TagUpload_"), name)
        XCTAssertTrue(name.hasSuffix(".csv"), name)
    }
}
