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

    func writeRosterCSV(_ rows: [(email: String, id: String, grade: String)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("roster.csv")
        var text = "Email,Student ID,Grade\n"
        for row in rows { text += "\(row.email),\(row.id),\(row.grade)\n" }
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
}
