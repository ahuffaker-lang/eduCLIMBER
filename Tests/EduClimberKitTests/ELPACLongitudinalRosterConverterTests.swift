import XCTest
@testable import EduClimberKit

final class ELPACLongitudinalRosterConverterTests: XCTestCase {
    let converter = ELPACLongitudinalRosterConverter()

    func answers(
        year: String = "2026-2027", tagNamePrefix: String = "ELPI Level ",
        includeTagFlag: String = "No", tagFlag: String? = nil
    ) -> [String: String] {
        var values = [
            "school_year": year, "tag_name_prefix": tagNamePrefix,
            "include_tag_flag": includeTagFlag,
        ]
        if let tagFlag { values["tag_flag"] = tagFlag }
        return values
    }

    private func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/elpac_longitudinal_roster.xlsx")
    }

    /// The fixture's four students (see `ELPACLongitudinalReaderTests`):
    /// Abundis (3L, most recent of several years), Acevedo (3H, a Summative
    /// result winning over a same-year Initial placeholder), Carrillo (no
    /// testing history at all -- flagged, not tagged), and Delgado (4).
    func testEachStudentGetsATagNameBuiltFromTheirOwnELPILevel() throws {
        let result = try Pipeline.convertFile(converter: converter, url: fixtureURL(), answers: answers())
        XCTAssertEqual(
            result.rows.map { $0["Student ID"] }, ["20212207", "20180241", "20220456"])
        XCTAssertEqual(result.rows[0]["Tag Name"], "ELPI Level 3L")
        XCTAssertEqual(result.rows[1]["Tag Name"], "ELPI Level 3H")
        XCTAssertEqual(result.rows[2]["Tag Name"], "ELPI Level 4")
        result.rows.forEach { XCTAssertEqual($0["School Year"], "2026-2027") }
    }

    func testCustomPrefixIsHonored() throws {
        let result = try Pipeline.convertFile(
            converter: converter, url: fixtureURL(),
            answers: answers(tagNamePrefix: "ELPI"))
        XCTAssertEqual(result.rows.first?["Tag Name"], "ELPI3L")
    }

    /// A student with no Academic Year on file yet has no level to tag them
    /// with, so they're flagged rather than silently skipped or guessed at.
    func testStudentWithNoCurrentYearELPIIsFlagged() throws {
        let result = try Pipeline.convertFile(converter: converter, url: fixtureURL(), answers: answers())
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("No current-year ELPI level") },
            "\(result.errors.map(\.description))")
        XCTAssertFalse(result.rows.contains { $0["Student ID"] == "20260003" })
    }

    func testRejectsAFileThatIsNotXLSX() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent("roster.csv")
        try "Student ID,Student Name\n20212318,\"Garcia, Ethan\"".write(
            to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try converter.loadSource(at: file)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("ELPAC Longitudinal Roster"), "\(error)")
        }
    }

    // MARK: - Tag Flag is off by default, per student request

    func testTagFlagColumnIsExcludedByDefault() throws {
        let result = try Pipeline.convertFile(converter: converter, url: fixtureURL(), answers: answers())
        XCTAssertFalse(result.columns.contains("Tag Flag"), "\(result.columns)")
    }

    func testTagFlagColumnIsIncludedWhenRequested() throws {
        let result = try Pipeline.convertFile(
            converter: converter, url: fixtureURL(),
            answers: answers(includeTagFlag: "Yes", tagFlag: "Y"))
        XCTAssertTrue(result.columns.contains("Tag Flag"), "\(result.columns)")
        XCTAssertEqual(result.rows.first?["Tag Flag"], "Y")
    }

    // MARK: - Student Roster fallback and deduplication

    /// `convert()` is called directly here (bypassing `loadSource`, which
    /// only accepts the real .xlsx export) with a hand-built table shaped
    /// like the reader's output.
    func testStudentRosterFallbackFillsAMissingName() throws {
        let rosterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("student_roster.csv")
        try StudentRosterStore.save(
            [StudentRosterEntry(studentID: "20212318", firstName: "Ethan", lastName: "Garcia")],
            to: rosterURL)
        let converterWithRoster = ELPACLongitudinalRosterConverter(rosterStoreURL: rosterURL)

        let table = Table(
            headers: ["Student ID", "Student Name", "Overall Performance Level"],
            rows: [[
                "Student ID": "20212318", "Student Name": "", "Overall Performance Level": "2H",
            ]])
        let columns: [String: String?] = [
            "student_id": "Student ID", "student_name": "Student Name",
            "elpi_level": "Overall Performance Level",
        ]
        let result = try converterWithRoster.convert(table: table, answers: answers(), columns: columns)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
        XCTAssertEqual(result.rows.first?["Tag Name"], "ELPI Level 2H")
    }

    func testDuplicateStudentIDsAreSkippedWithANotice() throws {
        let table = Table(
            headers: ["Student ID", "Student Name", "Overall Performance Level"],
            rows: [
                ["Student ID": "20212318", "Student Name": "Garcia, Ethan",
                 "Overall Performance Level": "2H"],
                ["Student ID": "20212318", "Student Name": "Garcia, Ethan",
                 "Overall Performance Level": "2H"],
            ])
        let columns: [String: String?] = [
            "student_id": "Student ID", "student_name": "Student Name",
            "elpi_level": "Overall Performance Level",
        ]
        let result = try converter.convert(table: table, answers: answers(), columns: columns)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.notices.count, 1)
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
        XCTAssertTrue(name.hasPrefix("eduCLIMBER_Upload_ELPACLongitudinalRosterTagUpload_"), name)
        XCTAssertTrue(name.hasSuffix(".csv"), name)
    }
}
