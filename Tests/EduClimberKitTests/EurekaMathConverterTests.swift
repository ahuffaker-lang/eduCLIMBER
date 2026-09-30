import XCTest
@testable import EduClimberKit

final class EurekaMathConverterTests: XCTestCase {
    let converter = EurekaMathConverter()
    let header = "assessment_id,attempt_id,template_id,assessment,assessment_status,"
        + "type_of_assessment,is_custom,grade,module,curriculum,school,teacher_sis_id,teacher,"
        + "section,student_email,student_id,student,date_launched,date_completed,"
        + "overall_points_achieved,overall_points_possible,overall_percentage,performance_band\n"

    func writeCSV(_ body: String, name: String = "source.csv") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try (header + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// A real row from the district's export (names/IDs are the actual sample
    /// given, not placeholders), with assessment_status changed to "done" --
    /// the happy-path fixture for tests that expect a clean conversion.
    /// `testOpenStatusIsFlaggedForReview` covers the original "open" status.
    let sampleMARow =
        "3d1955fc,5143f205,634064f8,\"Grade 5, Module 1, Module Assessment 1\",done,MA,FALSE,5,1,"
        + "em2cali,Christian Sorensen Elementary School,9033,\"Lawrence, Michael\","
        + "Grade 5 - Lawrence - 1,egarcia18@whittiercity.net,20212318,\"Garcia, Ethan\","
        + "9/25/26,9/25/26,4.41,27.5,16,not yet proficient\n"

    let sampleTQRow =
        "a62680fa,817d39c9,613de384,\"Grade 4, Module 1, Topic B Quiz 1\",done,TQ,FALSE,4,1,"
        + "em2cali,Daniel Phelan Elementary School,7187,\"Rodriguez, Mireya\","
        + "Grade 4 DI - Rodriguez - 1,ebarcena93@whittiercity.net,20211893,\"Barcena, Emma\","
        + "9/3/26,9/3/26,9,14,64,partially proficient\n"

    func answers(year: String = "2026-2027") -> [String: String] {
        ["school_year": year]
    }

    // MARK: - Filtering by type_of_assessment

    /// Only Module Assessment rows convert; a Topic Quiz row is skipped
    /// without becoming a problem.
    func testOnlyModuleAssessmentRowsConvert() throws {
        let url = try writeCSV(sampleMARow + sampleTQRow)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?["Student ID"], "20212318")
    }

    func testTypeOfAssessmentMatchIsCaseInsensitive() throws {
        let lowercase = sampleMARow.replacingOccurrences(of: ",MA,", with: ",ma,")
        let url = try writeCSV(lowercase)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertEqual(result.rows.count, 1)
    }

    func testFileWithOnlyNonModuleAssessmentsConvertsNothingAndReportsNoErrors() throws {
        let url = try writeCSV(sampleTQRow)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.isClean, "skipped rows are not problems")
    }

    // MARK: - Filtering by assessment_status

    /// A Module Assessment that is not yet "done" (the real "open" row from
    /// the district's sample, which already carries a full score) is flagged
    /// for review, not skipped and not converted silently.
    func testOpenStatusIsFlaggedForReview() throws {
        let openRow =
            "3d1955fc,5143f205,634064f8,\"Grade 5, Module 1, Module Assessment 1\",open,MA,FALSE,"
            + "5,1,em2cali,Christian Sorensen Elementary School,9033,\"Lawrence, Michael\","
            + "Grade 5 - Lawrence - 1,egarcia18@whittiercity.net,20212318,\"Garcia, Ethan\","
            + "9/25/26,9/25/26,4.41,27.5,16,not yet proficient\n"
        let url = try writeCSV(openRow)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertFalse(result.isClean)
        XCTAssertTrue(
            result.errors.contains { $0.message.contains("not \"done\"") },
            "\(result.errors.map(\.message))")
    }

    func testStatusMatchIsCaseInsensitive() throws {
        let uppercase = sampleMARow.replacingOccurrences(of: ",done,MA,", with: ",DONE,MA,")
        let url = try writeCSV(uppercase)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.count, 1)
    }

    // MARK: - Full row mapping

    func testFullRowMapping() throws {
        let url = try writeCSV(sampleMARow)
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first, [
            "Assessment Name": "Eureka Math Module",
            "Assessment Group": "Eureka Math",
            "Assessment Window": "Module 1",
            "School Year": "2026-2027",
            "Student ID": "20212318",
            "Student Last Name": "Garcia",
            "Student First Name": "Ethan",
            "Student Middle Initial": "",
            "Student Grade Level": "5",
            "Date of Birth": "",
            "Score": "16",
            "Score Detail 1 Proficiency Level": "not yet proficient",
            "Score Detail 2 Date Completed": "9/25/26",
        ])
    }

    /// The template's own example (86 / proficient) matches a real row in the
    /// district's sample data, confirming Score = overall_percentage and
    /// Score Detail 1 = performance_band.
    func testMatchesTheTemplatesOwnExample() throws {
        let url = try writeCSV(
            "3d1955fc,ec5b1313,634064f8,\"Grade 5, Module 1, Module Assessment 1\",done,MA,FALSE,"
            + "5,1,em2cali,Christian Sorensen Elementary School,9033,\"Lawrence, Michael\","
            + "Grade 5 - Lawrence - 1,schavarria53@whittiercity.net,20210953,"
            + "\"Chavarria, Sophie\",9/25/26,9/25/26,23.75,27.5,86,proficient\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Score"], "86")
        XCTAssertEqual(result.rows.first?["Score Detail 1 Proficiency Level"], "proficient")
    }

    // MARK: - Validation

    func testBlankRequiredFieldsAreFlagged() throws {
        // A non-empty attempt_id keeps this from being dropped as a blank row.
        let url = try writeCSV(",x,,,,MA,,,,,,,,,,,,,,,,,\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        let messages = result.errors.map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("Assessment Status is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Student Id is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Student is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Grade is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Module is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Date Completed is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Overall Percentage is blank") })
        XCTAssertTrue(messages.contains { $0.contains("Performance Band is blank") })
    }

    func testUnparseableStudentNameIsFlagged() throws {
        let url = try writeCSV(
            "3d1955fc,x,634064f8,x,done,MA,FALSE,5,1,x,x,9033,x,x,x,20212318,Ethan Garcia,"
            + "9/25/26,9/25/26,4.41,27.5,16,not yet proficient\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(
            result.errors[0].message.contains("is not in 'Last, First' format"),
            result.errors[0].message)
    }

    /// eduCLIMBER's Windows for this assessment are only Module 1-6.
    func testModuleOutsideOneToSixIsFlagged() throws {
        let url = try writeCSV(
            "3d1955fc,x,634064f8,x,done,MA,FALSE,5,7,x,x,9033,x,x,x,20212318,\"Garcia, Ethan\","
            + "9/25/26,9/25/26,4.41,27.5,16,not yet proficient\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.errors.contains { $0.message.contains("Module 1-6 windows") })
    }

    /// eduCLIMBER's "Eureka Math Grades 3-5" assessment does not cover K-2,
    /// even though a district-wide export could in principle include them.
    func testGradeOutsideThreeToFiveIsFlagged() throws {
        let url = try writeCSV(
            "3d1955fc,x,634064f8,x,done,MA,FALSE,2,1,x,x,9033,x,x,x,20212318,\"Garcia, Ethan\","
            + "9/25/26,9/25/26,4.41,27.5,16,not yet proficient\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers())
        XCTAssertTrue(result.errors.contains { $0.message.contains("Grades 3-5") })
    }

    // MARK: - School Year prompt defaults to the current academic year

    func testSchoolYearPromptDefaultsToCurrentAcademicYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let fall = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let spring = calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))!
        XCTAssertEqual(
            EurekaMathConverter.currentSchoolYear(referenceDate: fall, calendar: calendar),
            "2026-2027")
        XCTAssertEqual(
            EurekaMathConverter.currentSchoolYear(referenceDate: spring, calendar: calendar),
            "2026-2027")
    }

    func testPromptCarriesTheComputedDefault() {
        let prompt = try! XCTUnwrap(converter.prompts.first { $0.key == "school_year" })
        XCTAssertEqual(prompt.defaultValue, EurekaMathConverter.currentSchoolYear())
    }

    // MARK: - Output shape

    func testOutputColumnOrder() {
        // Assessment Name before Group, and Last Name before First -- the
        // reverse order from Running Records and HFW -- per this template.
        XCTAssertEqual(converter.outputColumns, [
            "Assessment Name", "Assessment Group", "Assessment Window", "School Year",
            "Student ID", "Student Last Name", "Student First Name", "Student Middle Initial",
            "Student Grade Level", "Date of Birth", "Score", "Score Detail 1 Proficiency Level",
            "Score Detail 2 Date Completed",
        ])
    }
}
