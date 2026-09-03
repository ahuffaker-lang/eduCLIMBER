import XCTest
@testable import EduClimberKit

/// Converter-level integration: the rubric feeds real rows through
/// `RunningRecordsConverter.convert`, not just the standalone tables tested in
/// BenchmarkRubricTests.
final class BenchmarkScoringTests: XCTestCase {
    let converter = RunningRecordsConverter()
    let header = "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"

    func writeCSV(_ body: String, name: String = "source.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try (header + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func answers(window: String = "Trimester 2", year: String = "2026-2027",
                 language: String = "English") -> [String: String] {
        ["assessment_window": window, "school_year": year, "language": language]
    }

    // MARK: - Fill blank / quality-check existing values

    /// English 2026-27, Grade 3 Trimester 2: P is a 4 ("P or above"). A blank
    /// sheet value is filled in with no notice.
    func testBlankProficiencyIsFilledSilently() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,3,P,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean)
        XCTAssertTrue(result.notices.isEmpty)
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "4")
    }

    /// A sheet value that already agrees with the rubric is left alone -- no notice.
    func testMatchingProficiencyProducesNoNotice() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,3,P,4\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.notices.isEmpty)
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "4")
    }

    /// A sheet value that disagrees is overwritten with the rubric's value, and
    /// the disagreement is surfaced as a non-blocking notice, not a problem.
    func testMismatchedProficiencyIsOverwrittenAndNoticed() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,3,P,2\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "a mismatch is a notice, not a problem")
        XCTAssertEqual(result.notices.count, 1)
        let message = try XCTUnwrap(result.notices.first?.message)
        XCTAssertTrue(message.contains("sheet Proficiency Level was '2'"), message)
        XCTAssertTrue(message.contains("English 2026-27"), message)
        XCTAssertTrue(message.contains("4"), message)
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "4")
    }

    // MARK: - Grades 6-8 are excluded and flagged

    /// Grades outside K-5 aren't blocked -- real files turn up grades the
    /// rubric doesn't plan for (a 6th grader in a Spanish file, for instance),
    /// and dropping the row would just push manual work back onto the user.
    /// The row exports with its existing Proficiency Level untouched, plus a
    /// notice explaining no benchmark was applied.
    func testGradesSixThroughEightPassThroughWithANotice() throws {
        for grade in ["6", "7", "8"] {
            let url = try writeCSV("\"Gomez, Maria\",1,\(grade),P,At Standard\n")
            let result = try Pipeline.convertFile(
                converter: converter, url: url, answers: answers())
            XCTAssertEqual(result.rows.count, 1, grade)
            XCTAssertTrue(result.isClean, grade)
            XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "At Standard", grade)
            XCTAssertEqual(result.notices.count, 1, grade)
            let message = try XCTUnwrap(result.notices.first?.message)
            XCTAssertTrue(message.contains("not covered by the English 2026-27 benchmark"), message)
        }
    }

    /// A grade the benchmark doesn't cover, with no existing Proficiency Level
    /// either, still exports -- just blank, same as it arrived.
    func testUnsupportedGradeWithNoExistingProficiencyExportsBlank() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,6,P,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers())
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "")
        XCTAssertEqual(result.notices.count, 1)
    }

    // MARK: - Kindergarten Trimester 1 has no scale and passes through

    func testKindergartenTrimesterOnePassesThroughWithANotice() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,K,A,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers(window: "Trimester 1"))
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertTrue(result.isClean)
        let message = try XCTUnwrap(result.notices.first?.message)
        XCTAssertTrue(message.contains("Kindergarten Trimester 1"), message)
        XCTAssertTrue(message.contains("no benchmark scale"), message)
        XCTAssertTrue(message.contains("English 2026-27"), message)
    }

    /// Kindergarten Trimester 2/3 do have a scale -- only Trimester 1 lacks one.
    func testKindergartenTrimesterTwoIsScored() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,K,C,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers(window: "Trimester 2"))
        XCTAssertTrue(result.isClean)
        XCTAssertTrue(result.notices.isEmpty)
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "3")
    }

    // MARK: - Unrecognized / blank grade

    func testBlankGradePassesThroughWithANotice() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,,P,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers())
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertTrue(result.isClean)
        let message = try XCTUnwrap(result.notices.first?.message)
        XCTAssertTrue(message.contains("Grade Level is blank"), message)
        XCTAssertTrue(message.contains("English 2026-27"), message)
    }

    func testUnrecognizedGradePassesThroughWithANotice() throws {
        let url = try writeCSV("\"Gomez, Maria\",1,TK,P,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url, answers: answers())
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertTrue(result.isClean)
        let message = try XCTUnwrap(result.notices.first?.message)
        XCTAssertTrue(message.contains("Grade Level 'TK' is not covered"), message)
    }

    // MARK: - Spanish scoring end to end

    /// Spanish only has one table, so the school year does not matter.
    func testSpanishScoringEndToEnd() throws {
        let url = try writeCSV("\"Cruz, Ana\",1,1,H,\n")
        let result = try Pipeline.convertFile(
            converter: converter, url: url,
            answers: answers(year: "2019-2020", language: "Spanish"))
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.rows.first?["Assessment Name"], "Independent Reading Level Spanish")
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "3")
    }

    // MARK: - Scoring table summary (the persistent "Benchmark: ..." line)

    func testScoringTableSummaryBeforeTheTwentyTwentySixCutover() {
        let summary = converter.scoringTableSummary(
            for: answers(year: "2025-2026"))
        XCTAssertEqual(summary?.text, "Benchmark: English 2019-20 · Grades K-5 scored, other grades pass through")
        XCTAssertFalse(summary?.isCarriedForward ?? true)
    }

    func testScoringTableSummaryAtTheTwentyTwentySixCutover() {
        let summary = converter.scoringTableSummary(
            for: answers(year: "2026-2027"))
        XCTAssertEqual(summary?.text, "Benchmark: English 2026-27 · Grades K-5 scored, other grades pass through")
        XCTAssertFalse(summary?.isCarriedForward ?? true)
    }

    func testScoringTableSummaryCarriesForwardPastItsEffectiveYear() {
        let summary = converter.scoringTableSummary(
            for: answers(year: "2028-2029"))
        XCTAssertEqual(summary?.text, "Benchmark: English 2026-27 · Grades K-5 scored, other grades pass through")
        XCTAssertTrue(summary?.isCarriedForward ?? false)
        XCTAssertEqual(summary?.carriedForwardNote, "no table for 2028-2029 yet")
    }

    func testScoringTableSummaryForSpanish() {
        let summary = converter.scoringTableSummary(
            for: answers(year: "2026-2027", language: "Spanish"))
        XCTAssertEqual(summary?.text, "Benchmark: Spanish 2021-22 · Grades K-5 scored, other grades pass through")
        XCTAssertFalse(summary?.isCarriedForward ?? true)
    }

    func testScoringTableSummaryIsNilWithoutBothAnswers() {
        XCTAssertNil(converter.scoringTableSummary(for: ["language": "English"]))
        XCTAssertNil(converter.scoringTableSummary(for: ["school_year": "2026-2027"]))
    }
}
