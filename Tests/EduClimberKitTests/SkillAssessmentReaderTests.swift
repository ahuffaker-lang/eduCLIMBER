import XCTest
@testable import EduClimberKit

/// Builds grids shaped like a real Skill Assessment Student List export, but
/// with invented teachers and students -- the real export has 17 columns
/// (A-Q) and leaves most of them blank.
final class SkillAssessmentReaderTests: XCTestCase {
    static func row(_ values: [Int: String]) -> [String] {
        var result = [String](repeating: "", count: 17)
        for (index, value) in values { result[index] = value }
        return result
    }

    let titleRow = ["Skills Assessment Student List"]

    func assessmentRow(assessment: String, teacher: String, date: String = "01-01-2026") -> [String] {
        Self.row([0: "Assessment:\nTeacher:\nDate:",
                  3: "\(assessment)\n\(teacher)\nControl Panel (\(date))"])
    }

    let headerRow = row([
        0: "Student", 4: "ID", 5: "Total Attempts", 7: "Last Assessed",
        8: "#\nCorrect", 9: "#\nIncorrect", 10: "#\nAnswered", 11: "#\nPossible",
        12: "%\nEarned", 13: "Correct Questions",
    ])

    func studentRow(
        number: Int, name: String, id: String, attempts: String = "1",
        lastAssessed: String = "01/01/2026", correct: String = "10", incorrect: String = "0",
        answered: String = "10", possible: String = "10", percent: String = "100.0%",
        correctQuestions: String = "a, b, c"
    ) -> [String] {
        row([0: "\(number).", 2: name, 4: id, 5: attempts, 7: lastAssessed, 8: correct,
             9: incorrect, 10: answered, 11: possible, 12: percent, 13: correctQuestions])
    }

    func footerRow(page: String = "Page 1 of 1") -> [String] {
        row([1: "Generated on 01/01/2026 by Renaissance Learning, Inc.\nhelp.illuminateed.com",
             14: page])
    }

    // MARK: - Row classification

    func testClassifiesTitleRowAsOther() {
        XCTAssertEqual(SkillAssessmentReader.classify(titleRow), .other)
    }

    func testClassifiesAssessmentRow() {
        let classified = SkillAssessmentReader.classify(
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Bednarik, Amanda N."))
        XCTAssertEqual(classified, .assessment(name: "26-27 Sample Skill", teacher: "Bednarik, Amanda N."))
    }

    func testClassifiesHeaderRow() {
        XCTAssertEqual(SkillAssessmentReader.classify(headerRow), .header)
    }

    func testClassifiesStudentRow() {
        let classified = SkillAssessmentReader.classify(
            studentRow(number: 1, name: "Flores, Alexander", id: "20221371"))
        XCTAssertEqual(classified, .student)
    }

    func testClassifiesFooterRowAsOther() {
        XCTAssertEqual(SkillAssessmentReader.classify(footerRow()), .other)
    }

    func testStudentRowNumberRecognizesOnlyDigitsFollowedByADot() {
        XCTAssertTrue(SkillAssessmentReader.isStudentRowNumber("1."))
        XCTAssertTrue(SkillAssessmentReader.isStudentRowNumber("23."))
        XCTAssertFalse(SkillAssessmentReader.isStudentRowNumber("1"))
        XCTAssertFalse(SkillAssessmentReader.isStudentRowNumber("."))
        XCTAssertFalse(SkillAssessmentReader.isStudentRowNumber(""))
        XCTAssertFalse(SkillAssessmentReader.isStudentRowNumber("a."))
    }

    // MARK: - Header validation

    func testValidateHeaderAcceptsTheRealShape() throws {
        try SkillAssessmentReader.validateHeader(headerRow)
    }

    func testValidateHeaderRejectsAMismatchedColumn() {
        var badHeader = headerRow
        badHeader[4] = "Student ID"  // the real export just has "ID" here
        XCTAssertThrowsError(try SkillAssessmentReader.validateHeader(badHeader)) { error in
            let message = (error as? ConverterError)?.message ?? ""
            XCTAssertTrue(message.contains("column E"), message)
            XCTAssertTrue(message.contains("\"ID\""), message)
        }
    }

    // MARK: - Flattening

    func testFlattenProducesOneRowPerStudentWithTeacherAttached() throws {
        let grid = [
            titleRow,
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Alvarado, Maria"),
            headerRow,
            studentRow(number: 1, name: "Flores, Alexander", id: "20221371"),
            studentRow(number: 2, name: "Guerrero, Aitana", id: "20220713"),
            footerRow(),
        ]
        let table = try SkillAssessmentReader.flatten(grid)
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0]["Teacher"], "Alvarado, Maria")
        XCTAssertEqual(table.rows[0]["Student Name"], "Flores, Alexander")
        XCTAssertEqual(table.rows[0]["Student ID"], "20221371")
        XCTAssertEqual(table.rows[0]["Assessment Name"], "26-27 Sample Skill")
    }

    func testFlattenHandlesTwoTeachers() throws {
        let grid = [
            titleRow,
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Alvarado, Maria"),
            headerRow,
            studentRow(number: 1, name: "Flores, Alexander", id: "20221371"),
            footerRow(page: "Page 1 of 2"),
            titleRow,
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Apodaca, Vanessa"),
            headerRow,
            studentRow(number: 1, name: "Ponce, Ezekiel", id: "20222089"),
            footerRow(page: "Page 2 of 2"),
        ]
        let table = try SkillAssessmentReader.flatten(grid)
        XCTAssertEqual(table.rows.map { $0["Teacher"] }, ["Alvarado, Maria", "Apodaca, Vanessa"])
    }

    /// A class that runs past a printed page repeats the Title/Assessment/
    /// Header block for the *same* teacher mid-roster. Nothing here deletes
    /// that repeated block, but no student should be lost or duplicated.
    func testARepeatedBlockForTheSameTeacherDoesNotLoseOrDuplicateStudents() throws {
        let grid = [
            titleRow,
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Bednarik, Amanda N."),
            headerRow,
            studentRow(number: 1, name: "One, Student", id: "11111111"),
            studentRow(number: 2, name: "Two, Student", id: "22222222"),
            footerRow(page: "Page 1 of 2"),
            titleRow,
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Bednarik, Amanda N."),
            headerRow,
            studentRow(number: 3, name: "Three, Student", id: "33333333"),
            footerRow(page: "Page 2 of 2"),
        ]
        let table = try SkillAssessmentReader.flatten(grid)
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows.map { $0["Student ID"] }, ["11111111", "22222222", "33333333"])
        XCTAssertTrue(table.rows.allSatisfy { $0["Teacher"] == "Bednarik, Amanda N." })
    }

    func testFlattenPreservesMessyCorrectQuestionsSpacingForTheConverterToClean() throws {
        let grid = [
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Alvarado, Maria"),
            headerRow,
            studentRow(
                number: 1, name: "Flores, Alexander", id: "20221371",
                correctQuestions: "a , b , c  , d"),
        ]
        let table = try SkillAssessmentReader.flatten(grid)
        XCTAssertEqual(table.rows[0]["Correct Questions"], "a , b , c  , d")
    }

    func testFlattenThrowsWhenNoHeaderRowIsFound() {
        let grid = [titleRow, assessmentRow(assessment: "X", teacher: "Y")]
        XCTAssertThrowsError(try SkillAssessmentReader.flatten(grid)) { error in
            XCTAssertTrue((error as? ConverterError)?.message.contains("no \"Student\" header") == true)
        }
    }

    func testFlattenThrowsWhenNoStudentRowsAreFound() {
        let grid = [
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Alvarado, Maria"), headerRow,
        ]
        XCTAssertThrowsError(try SkillAssessmentReader.flatten(grid)) { error in
            XCTAssertTrue((error as? ConverterError)?.message.contains("No student rows") == true)
        }
    }

    func testFlattenThrowsOnAMismatchedHeaderEvenWithStudentRowsPresent() {
        var badHeader = headerRow
        badHeader[4] = "Student ID"
        let grid = [
            assessmentRow(assessment: "26-27 Sample Skill", teacher: "Alvarado, Maria"), badHeader,
            studentRow(number: 1, name: "Flores, Alexander", id: "20221371"),
        ]
        XCTAssertThrowsError(try SkillAssessmentReader.flatten(grid))
    }

    // MARK: - Reading a real .xlsx file end to end

    func testReadsARealShapedXLSXFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/skill_assessment_student_list.xlsx")
        let table = try SkillAssessmentReader.read(contentsOf: url)
        XCTAssertEqual(table.headers, SkillAssessmentReader.outputHeaders)
        XCTAssertFalse(table.rows.isEmpty)
        XCTAssertTrue(table.rows.allSatisfy { !($0["Student ID"] ?? "").isEmpty })
        XCTAssertTrue(table.rows.allSatisfy { !($0["Teacher"] ?? "").isEmpty })
    }
}
