import XCTest
@testable import EduClimberKit

/// This converter is a thin wrapper: `loadSource` runs the ELPAC Longitudinal
/// Roster file through `ELPACLongitudinalReader`, and everything else --
/// column matching, Student ID/name resolution, deduplication, the Student
/// Roster fallback, prompts, naming -- is delegated to a plain
/// `TagUploadConverter`. `TagUploadConverterTests` already covers that
/// delegated behavior in depth, so these tests focus on the two things this
/// type adds: reading the real export shape, and forwarding everything else
/// unchanged.
final class ELPACLongitudinalRosterConverterTests: XCTestCase {
    let converter = ELPACLongitudinalRosterConverter()

    func answers(
        year: String = "2026-2027", tagName: String = "EL Students", tagFlag: String? = "Y"
    ) -> [String: String] {
        var values = ["school_year": year, "tag_name": tagName]
        if let tagFlag { values["tag_flag"] = tagFlag }
        return values
    }

    func testEndToEndConvertsTheMostRecentYearForEachStudent() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/elpac_longitudinal_roster.xlsx")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(
            result.rows.map { $0["Student ID"] },
            ["20212207", "20180241", "20260003", "20220456"])
        XCTAssertEqual(result.rows[0]["Student First Name"], "Kataleah C.")
        XCTAssertEqual(result.rows[0]["Student Last Name"], "Abundis")
        result.rows.forEach {
            XCTAssertEqual($0["School Year"], "2026-2027")
            XCTAssertEqual($0["Tag Name"], "EL Students")
            XCTAssertEqual($0["Tag Flag"], "Y")
        }
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

    // MARK: - Delegation to TagUploadConverter

    func testPromptsMatchTagUpload() {
        XCTAssertEqual(
            converter.prompts.map(\.key), TagUploadConverter().prompts.map(\.key))
    }

    func testOutputColumnsMatchTagUpload() {
        XCTAssertEqual(converter.outputColumns, TagUploadConverter().outputColumns)
    }

    func testDefaultOutputNameMatchesTagUpload() {
        XCTAssertEqual(
            converter.defaultOutputName(answers: answers()),
            TagUploadConverter().defaultOutputName(answers: answers()))
    }

    /// `convert()` is called directly here (bypassing `loadSource`, which
    /// only accepts the real .xlsx export) to prove the roster-aware
    /// `TagUploadConverter` underneath is what actually runs.
    func testStudentRosterFallbackStillApplies() throws {
        let rosterURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("student_roster.csv")
        try StudentRosterStore.save(
            [StudentRosterEntry(studentID: "20212318", firstName: "Ethan", lastName: "Garcia")],
            to: rosterURL)
        let converterWithRoster = ELPACLongitudinalRosterConverter(rosterStoreURL: rosterURL)

        let table = Table(
            headers: ["Student ID", "Student First Name", "Student Last Name"],
            rows: [["Student ID": "20212318", "Student First Name": "", "Student Last Name": ""]])
        let columns: [String: String?] = [
            "student_id": "Student ID", "first_name": "Student First Name",
            "last_name": "Student Last Name", "student": nil,
        ]
        let result = try converterWithRoster.convert(table: table, answers: answers(), columns: columns)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Ethan")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Garcia")
    }
}
