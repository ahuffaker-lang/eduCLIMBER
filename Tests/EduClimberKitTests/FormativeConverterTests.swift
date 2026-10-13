import XCTest
@testable import EduClimberKit

final class FormativeConverterTests: XCTestCase {
    let converter = FormativeConverter()
    let header = "Timestamp,Org,Teacher ID,Teacher name,Class ID,Class,Student ID,Email/username,"
        + "Last name,First name,Total score (%),Total score (points),Points possible,Q1 - Score\n"

    func writeCSV(_ body: String, name: String = "formative.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try (header + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Mirrors the real roster's exact header -- Student ID, Grade, School,
    /// StuEmail, First Name, Last Name. First/Last Name are blank by default
    /// (falls back to Formative's own name, matching most tests); pass
    /// `names` keyed by email to test the roster's name taking precedence.
    func writeRosterCSV(
        _ rows: [(email: String, id: String, grade: String)],
        emailHeader: String = "StuEmail",
        names: [String: (first: String, last: String)] = [:]
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("roster.csv")
        var text = "Student ID,Grade,School,\(emailHeader),First Name,Last Name\n"
        for row in rows {
            let name = names[row.email] ?? (first: "", last: "")
            text += "\(row.id),\(row.grade),Edwards,\(row.email),\(name.first),\(name.last)\n"
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // A real-shaped rollup row (blank Student ID/Email) -- a "Totals" line.
    let totalsRow = "Totals,,,,,,,,,,42,794.9,1872,28\n"
    // A real-shaped school subtotal row -- also no Student ID/Email.
    let schoolSubtotalRow = ",Katherine Edwards Middle,,,,,,,,,40,653,\"1,504\",30\n"

    let submittedRow =
        "\"10/2/2026, 9:14:50 AM\",Katherine Edwards Middle,migrated-516773,Andrea St. John,"
        + "6a972feb3923f362ab069487,ELA and Social Studies - St. John,"
        + "6aa35b06dfcecc915a66a9ba,ahernandezzepeda54@whittiercity.net,Hernandez Zepeda,Agustin,"
        + "44,3.5,8,0\n"

    let notSubmittedRow =
        ",Katherine Edwards Middle,migrated-516773,Andrea St. John,6a972feb3923f362ab069487,"
        + "ELA and Social Studies - St. John,6324db286fc1109e2a623ec0,dmancera19@whittiercity.net,"
        + "Mancera,Delylah,,,,\n"

    func answers(rosterPath: String) -> [String: String] {
        [
            "assessment_name": "Benchmark 1: Origins of Civilization",
            "assessment_window": "Test 1",
            "school_year": "2026-2027",
            "roster_file": rosterPath,
        ]
    }

    func convert(_ url: URL, answers: [String: String]) throws -> ConversionResult {
        try Pipeline.convertFile(converter: converter, url: url, answers: answers)
    }

    // MARK: - Skipping rollup rows

    func testRollupRowsAreSkippedSilently() throws {
        let roster = try writeRosterCSV([(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")])
        let url = try writeCSV(totalsRow + schoolSubtotalRow + submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.count, 1)
    }

    // MARK: - Full row mapping

    func testFullRowMapping() throws {
        let roster = try writeRosterCSV([(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")])
        let url = try writeCSV(submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first, [
            "Assessment Group": "Social Studies Benchmarks",
            "Assessment Name": "Benchmark 1: Origins of Civilization",
            "Assessment Window": "Test 1",
            "School Year": "2026-2027",
            "Student ID": "20221371",
            "Student First Name": "Agustin",
            "Student Middle Initial": "",
            "Student Last Name": "Hernandez Zepeda",
            "Date of Birth": "",
            "Student Grade Level": "6",
            "Score": "44",
        ])
    }

    func testRosterEmailMatchIsCaseInsensitive() throws {
        let roster = try writeRosterCSV([(email: "AHernandezZepeda54@WhittierCity.net", id: "20221371", grade: "6")])
        let url = try writeCSV(submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student ID"], "20221371")
    }

    /// "Email" is kept as a fallback alongside the real "StuEmail" header.
    func testRosterAcceptsPlainEmailHeaderToo() throws {
        let roster = try writeRosterCSV(
            [(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")],
            emailHeader: "Email")
        let url = try writeCSV(submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student ID"], "20221371")
    }

    // MARK: - Not yet submitted

    func testNotSubmittedIsFlaggedButDoesNotBlockOtherRows() throws {
        let roster = try writeRosterCSV([
            (email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6"),
            (email: "dmancera19@whittiercity.net", id: "20221372", grade: "6"),
        ])
        let url = try writeCSV(submittedRow + notSubmittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertEqual(result.rows.count, 1, "only the submitted row should convert")
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("has not yet submitted") },
            "\(result.errors.map(\.message))")
    }

    func testNotSubmittedStudentsAreCollectedIntoAFollowUpReport() throws {
        let roster = try writeRosterCSV([
            (email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6"),
            (email: "dmancera19@whittiercity.net", id: "20221372", grade: "6"),
        ])
        let url = try writeCSV(submittedRow + notSubmittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        let followUp = try XCTUnwrap(result.followUpReport)
        XCTAssertEqual(followUp.title, "Not Yet Submitted")
        XCTAssertEqual(followUp.rows.count, 1)
        XCTAssertEqual(followUp.rows.first?["Email"], "dmancera19@whittiercity.net")
    }

    func testNoFollowUpReportWhenEveryoneSubmitted() throws {
        let roster = try writeRosterCSV([(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")])
        let url = try writeCSV(submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertNil(result.followUpReport)
    }

    // MARK: - Roster name overrides Formative's (sometimes truncated) name

    func testRosterNameOverridesFormativesOwnName() throws {
        // Formative's own export sometimes truncates a last name to a
        // single letter (seen for real as "G, Matthew" instead of
        // "Garcia, Matthew"); the roster is the district's own student
        // list, so it wins whenever it has a name at all.
        let roster = try writeRosterCSV(
            [(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")],
            names: ["ahernandezzepeda54@whittiercity.net": (first: "Agustin", last: "Hernandez-Zepeda")])
        let truncatedRow = submittedRow.replacingOccurrences(
            of: "Hernandez Zepeda,Agustin", with: "H,Agustin")
        let url = try writeCSV(truncatedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Hernandez-Zepeda")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Agustin")
    }

    func testFormativesNameIsUsedWhenTheRosterHasNone() throws {
        let roster = try writeRosterCSV([(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")])
        let url = try writeCSV(submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Hernandez Zepeda")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Agustin")
    }

    // MARK: - The roster join

    func testEmailNotInRosterIsFlagged() throws {
        let roster = try writeRosterCSV([(email: "someone-else@whittiercity.net", id: "99999999", grade: "6")])
        let url = try writeCSV(submittedRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("was not found in the roster") },
            "\(result.errors.map(\.message))")
    }

    func testThrowsWhenRosterFileCannotBeRead() {
        let url = try! writeCSV(submittedRow)
        XCTAssertThrowsError(
            try convert(url, answers: answers(rosterPath: "/nonexistent/roster.csv"))
        ) { error in
            XCTAssertTrue(
                (error as? ConverterError)?.message.contains("Could not read the roster") == true)
        }
    }

    // MARK: - Score parsing

    func testScoreIsTheBarePercentNumber() throws {
        let roster = try writeRosterCSV([(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")])
        let percentRow = submittedRow.replacingOccurrences(of: ",44,3.5,8,0", with: ",88,7,8,1")
        let url = try writeCSV(percentRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Score"], "88")
    }

    func testUnparseableScoreIsFlagged() throws {
        let roster = try writeRosterCSV([(email: "ahernandezzepeda54@whittiercity.net", id: "20221371", grade: "6")])
        let badRow = submittedRow.replacingOccurrences(of: ",44,3.5,8,0", with: ",N/A,3.5,8,0")
        let url = try writeCSV(badRow)
        let result = try convert(url, answers: answers(rosterPath: roster.path))
        XCTAssertTrue(result.errors.contains { $0.message.contains("Total score (%) 'N/A'") })
    }

    // MARK: - Output shape

    func testOutputColumnOrder() {
        XCTAssertEqual(converter.outputColumns, [
            "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
            "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
            "Date of Birth", "Student Grade Level", "Score",
        ])
    }

    func testAssessmentWindowIsAFixedChoice() {
        let prompt = converter.prompts.first { $0.key == "assessment_window" }
        XCTAssertEqual(prompt?.choices, ["Test 1", "Test 2", "Test 3"])
    }

    // MARK: - Duplicate submissions

    /// Same Student ID and Timestamp as `submittedRow`, but pushed through a
    /// second class roster -- exactly the real case found in the district's
    /// export (same submission, two Class values).
    let duplicateOfSubmittedRow =
        "\"10/2/2026, 9:14:50 AM\",Katherine Edwards Middle,migrated-516773,Andrea St. John,"
        + "deadbeefdeadbeefdeadbeef,P. 2 - Social Studies,"
        + "6aa35b06dfcecc915a66a9ba,ahernandezzepeda54@whittiercity.net,Hernandez Zepeda,Agustin,"
        + "44,3.5,8,0\n"

    func testDuplicateGroupsFindsRowsSharingAStudentID() throws {
        let url = try writeCSV(submittedRow + duplicateOfSubmittedRow)
        let table = try converter.loadSource(at: url)
        XCTAssertEqual(converter.duplicateGroups(in: table), [[0, 1]])
    }

    func testDuplicateGroupsIgnoresRowsWithUniqueIDs() throws {
        let url = try writeCSV(submittedRow)
        let table = try converter.loadSource(at: url)
        XCTAssertEqual(converter.duplicateGroups(in: table), [])
    }

    func testDuplicateGroupsIgnoresRollupRows() throws {
        // Rollup rows have no Student ID at all, so they must never be
        // grouped together as if they were the same "duplicate" student.
        let url = try writeCSV(totalsRow + schoolSubtotalRow)
        let table = try converter.loadSource(at: url)
        XCTAssertEqual(converter.duplicateGroups(in: table), [])
    }

    func testDuplicateGroupLabelUsesTheStudentsName() throws {
        let url = try writeCSV(submittedRow + duplicateOfSubmittedRow)
        let table = try converter.loadSource(at: url)
        XCTAssertEqual(
            converter.duplicateGroupLabel(for: table, firstRowIndex: 0), "Hernandez Zepeda, Agustin")
    }

    func testDuplicatePickerColumnsDistinguishTheCopies() {
        XCTAssertEqual(
            converter.duplicatePickerColumns, ["Class", "Teacher name", "Timestamp", "Total score (%)"])
    }
}
