import XCTest
@testable import EduClimberKit

/// The student name can arrive as one "Last, First" column or as separate
/// First Name / Last Name columns; both must land in the eduCLIMBER format.
final class StudentNameTests: XCTestCase {
    let converter = RunningRecordsConverter()
    let answers = ["assessment_window": "Trimester 2", "school_year": "2026-2027",
                   "language": "English"]

    let splitHeader = "First Name,Last Name,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
    let combinedHeader = "Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"

    func write(_ header: String, _ body: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("source.csv")
        try (header + body).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Split First Name / Last Name

    func testSplitNameColumnsConvertWithoutAsking() throws {
        let url = try write(splitHeader, "Maria,Gomez,100234,K,Below A,At Standard\n")
        let table = try Pipeline.loadSource(at: url)
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        XCTAssertFalse(mapping.needsConfirmation, "a split-name file should not prompt")
        XCTAssertEqual(converter.problems(for: mapping), [])

        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student First Name"], "Maria")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Gomez")
        XCTAssertEqual(result.rows.first?["Score"], "1")
    }

    func testSplitNamesAreTrimmedAndKeepMultiWordSurnames() throws {
        let url = try write(splitHeader, "  Anna Lee , Van Dyke ,100237,3,M,At Standard\n")
        let row = try XCTUnwrap(
            Pipeline.convertFile(converter: converter, url: url, answers: answers).rows.first)
        XCTAssertEqual(row["Student First Name"], "Anna Lee")
        XCTAssertEqual(row["Student Last Name"], "Van Dyke")
    }

    func testBlankHalfOfASplitNameIsFlagged() throws {
        let url = try write(splitHeader, "Maria,,100234,K,A,At Standard\n")
        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(result.errors[0].message.contains("Last Name is blank"),
                      result.errors[0].message)
        // The row is still identifiable in the error message.
        XCTAssertTrue(result.errors[0].message.contains("Maria"), result.errors[0].message)
    }

    func testSplitNameHeaderVariantsStillMatch() throws {
        let header = "student first name,STUDENT LAST NAME,Student ID,Grade,Reading Level,Proficiency\n"
        let url = try write(header, "Maria,Gomez,100234,K,C,At Standard\n")
        let table = try Pipeline.loadSource(at: url)
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        XCTAssertEqual(mapping.match(for: "first_name")?.header, "student first name")
        XCTAssertEqual(mapping.match(for: "last_name")?.header, "STUDENT LAST NAME")

        let result = try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        XCTAssertTrue(result.isClean, "\(result.errors.map(\.description))")
        XCTAssertEqual(result.rows.first?["Student Last Name"], "Gomez")
    }

    // MARK: - Combined "Last, First"

    func testCombinedNameColumnStillWorks() throws {
        let url = try write(combinedHeader, "\"Gomez, Maria\",100234,K,Below A,At Standard\n")
        let table = try Pipeline.loadSource(at: url)
        XCTAssertFalse(Pipeline.matchColumns(converter: converter, table: table).needsConfirmation)

        let row = try XCTUnwrap(
            Pipeline.convertFile(converter: converter, url: url, answers: answers).rows.first)
        XCTAssertEqual(row["Student First Name"], "Maria")
        XCTAssertEqual(row["Student Last Name"], "Gomez")
    }

    func testCombinedColumnIsNotConfusedWithFirstNameColumn() throws {
        // "Student" must not be offered as the likely "First Name" column, and
        // vice versa -- the two shapes have to stay distinguishable.
        let url = try write(combinedHeader, "\"Gomez, Maria\",100234,K,A,At Standard\n")
        let table = try Pipeline.loadSource(at: url)
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        XCTAssertNil(mapping.match(for: "first_name")?.header)
        XCTAssertFalse(mapping.match(for: "first_name")?.suggestions.contains("Student") ?? false)
    }

    // MARK: - Both, and neither

    func testSplitColumnsWinWhenTheFileHasBoth() throws {
        let header = "Student,First Name,Last Name,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
        let url = try write(header, "\"Wrong, Value\",Maria,Gomez,100234,K,A,At Standard\n")
        let row = try XCTUnwrap(
            Pipeline.convertFile(converter: converter, url: url, answers: answers).rows.first)
        XCTAssertEqual(row["Student First Name"], "Maria")
        XCTAssertEqual(row["Student Last Name"], "Gomez")
    }

    func testCombinedColumnFillsInForABlankSplitRow() throws {
        let header = "Student,First Name,Last Name,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
        let url = try write(header, "\"Gomez, Maria\",,,100234,K,A,At Standard\n")
        let row = try XCTUnwrap(
            Pipeline.convertFile(converter: converter, url: url, answers: answers).rows.first)
        XCTAssertEqual(row["Student First Name"], "Maria")
        XCTAssertEqual(row["Student Last Name"], "Gomez")
    }

    func testFileWithNoNameColumnAtAllIsExplained() throws {
        let url = try write("Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n",
                            "100234,K,A,At Standard\n")
        let table = try Pipeline.loadSource(at: url)
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        let problems = converter.problems(for: mapping)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("'First Name' and 'Last Name'"), problems[0])

        XCTAssertThrowsError(
            try Pipeline.convertFile(converter: converter, url: url, answers: answers)
        ) { error in
            XCTAssertTrue(
                (error as? ConverterError)?.message.contains("needs the student name") ?? false,
                "\(error)")
        }
    }

    func testOnlyOneHalfOfTheSplitPairIsNotEnough() throws {
        let url = try write("First Name,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n",
                            "Maria,100234,K,A,At Standard\n")
        let table = try Pipeline.loadSource(at: url)
        let mapping = Pipeline.matchColumns(converter: converter, table: table)
        XCTAssertEqual(converter.problems(for: mapping).count, 1)
    }
}
