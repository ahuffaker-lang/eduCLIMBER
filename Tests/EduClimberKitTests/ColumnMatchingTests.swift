import XCTest
@testable import EduClimberKit

/// Matching expected columns to real headers, including misspelled ones.
final class ColumnMatchingTests: XCTestCase {
    let converter = RunningRecordsConverter()
    let answers = ["assessment_window": "Trimester 1", "school_year": "2026-2027"]
    let goodHeader = "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
    let typoHeader = "Studnt,Student ID,Grade Level,Readng Levl (A-Z),Proficiency Level\n"
    let row = "\"Gomez, Maria\",100234,K,Below A,At Standard\n"

    func table(_ header: String) -> Table {
        try! makeTable(fromGrid: CSVReader.parse(header + row))
    }

    func testCleanHeadersNeedNoQuestions() {
        let mapping = Pipeline.matchColumns(converter: converter, table: table(goodHeader))
        XCTAssertFalse(mapping.needsConfirmation)
        XCTAssertEqual(mapping.match(for: "reading_level")?.header, "Reading Level (A-Z)")
    }

    func testMisspelledHeadersAreAskedAboutNotGuessed() {
        let mapping = Pipeline.matchColumns(converter: converter, table: table(typoHeader))
        XCTAssertEqual(
            Set(mapping.unsettled.map(\.column.key)), ["student", "reading_level"])
        // ...but the closest header is offered first, ready to be accepted.
        XCTAssertEqual(mapping.match(for: "student")?.suggestions.first, "Studnt")
        XCTAssertEqual(
            mapping.match(for: "reading_level")?.suggestions.first, "Readng Levl (A-Z)")
    }

    func testAutoMatchedHeaderIsNotSuggestedForAnotherColumn() {
        // "Student ID" belongs to student_id, so it must not be the top guess
        // for a misspelled "Student".
        let mapping = Pipeline.matchColumns(converter: converter, table: table(typoHeader))
        let suggestions = mapping.match(for: "student")?.suggestions ?? []
        XCTAssertFalse(suggestions.contains("Student ID"))
    }

    func testRenamedColumnIsSuggested() {
        let header = "Student,Student ID,Grade Level,Rdg Level A-Z,Proficiency Level\n"
        let mapping = Pipeline.matchColumns(converter: converter, table: table(header))
        XCTAssertEqual(
            mapping.match(for: "reading_level")?.suggestions.first, "Rdg Level A-Z")
    }

    func testConfirmedChoiceMakesTheConversionRun() throws {
        let loaded = table(typoHeader)
        var mapping = Pipeline.matchColumns(converter: converter, table: loaded)
        mapping.apply(["student": "Studnt", "reading_level": "Readng Levl (A-Z)"])
        XCTAssertFalse(mapping.needsConfirmation)

        let result = try Pipeline.convert(
            converter: converter, table: loaded, answers: answers, mapping: mapping)
        XCTAssertTrue(result.isClean)
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Gomez")
        XCTAssertEqual(result.rows.first?["Score"], "1")
    }

    func testSameHeaderCannotFeedTwoExpectedColumns() {
        var mapping = Pipeline.matchColumns(converter: converter, table: table(typoHeader))
        mapping.apply(["student": "Studnt", "reading_level": "Studnt"])
        XCTAssertTrue(
            mapping.problems().contains { $0.contains("more than one expected column") },
            "\(mapping.problems())")
        XCTAssertThrowsError(
            try Pipeline.convert(
                converter: converter, table: table(typoHeader),
                answers: answers, mapping: mapping))
    }

    func testRequiredColumnLeftUnsetIsReported() {
        var mapping = Pipeline.matchColumns(converter: converter, table: table(typoHeader))
        mapping.apply(["student": "Studnt", "reading_level": nil])
        XCTAssertEqual(mapping.problems(), ["No column chosen for 'Reading Level (A-Z)'."])
    }

    /// The name columns are optional individually -- the converter is what
    /// requires one shape or the other -- so both layers have to be checked.
    func testNameColumnsAreRequiredByTheConverterNotPerColumn() {
        var mapping = Pipeline.matchColumns(converter: converter, table: table(typoHeader))
        mapping.apply(["student": nil, "reading_level": "Readng Levl (A-Z)"])
        XCTAssertEqual(mapping.problems(), [], "no single name column is required on its own")
        XCTAssertEqual(converter.problems(for: mapping).count, 1)
        XCTAssertTrue(
            converter.problems(for: mapping)[0].contains("needs the student name"),
            converter.problems(for: mapping)[0])
    }

    func testUnmatchedMessageNamesTheClosestHeader() {
        let mapping = Pipeline.matchColumns(converter: converter, table: table(typoHeader))
        let message = mapping.unmatchedMessage()
        XCTAssertTrue(message.contains("Reading Level (A-Z)"), message)
        XCTAssertTrue(message.contains("Readng Levl (A-Z)"), message)
    }

    func testOptionalColumnWithNoLookalikeNeedsNoQuestion() {
        let optional = SourceColumn(
            key: "dob", label: "Date of Birth", isRequired: false)
        let mapping = resolveColumns(table: table(goodHeader), columns: [optional])
        XCTAssertFalse(mapping.needsConfirmation)
        XCTAssertNil(mapping.match(for: "dob")?.header)
    }

    func testEditDistanceRatio() {
        XCTAssertEqual(editDistanceRatio("student", "student"), 1.0)
        XCTAssertEqual(editDistance("student", "studnt"), 1)
        XCTAssertGreaterThan(editDistanceRatio("student", "studnt"), 0.8)
        XCTAssertLessThan(editDistanceRatio("student", "proficiency"), 0.45)
    }
}
