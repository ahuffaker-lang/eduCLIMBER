import Foundation

/// Reads an Illuminate "ELPAC Longitudinal Roster" export into a flat `Table`,
/// one row per student holding only that student's most recent Academic Year.
///
/// The source is nested two levels deep, not a plain table: one "student
/// header" row (Student Name, Student ID, a single current English
/// Proficiency summary code) is followed by one row per Academic Year of
/// that student's ELPAC testing history (Test Purpose, Test Grade Level,
/// Overall Performance Level) -- Name and Student ID are blank on every one
/// of those year rows -- before the next student's header row begins. On top
/// of that, the report repeats its title/filter-legend/column-header block
/// every printed page, a handful of students at a time, the same kind of
/// repeated-block noise the Skill Assessment Student List export has, just
/// shaped around pages instead of teachers. Row classification below only
/// looks at whether a row has a plausible Student Name + numeric Student ID
/// (a header row) or a year-shaped Academic Year (a year row); everything
/// else -- titles, filter legends, column headers, page footers -- falls
/// through as noise and is skipped, wherever in the file it appears.
///
/// A tag only needs to know where a student stands *now*, not their whole
/// testing history, so each student's year rows are collapsed down to just
/// one. That one is the most recent year that actually produced an Overall
/// Performance Level -- not simply the most recent year attempted. An
/// "Initial" row is a placeholder with no score until the Summative test is
/// scored, and an "Alternate ELPAC" administration (for students with
/// significant cognitive disabilities) never populates this column at all;
/// either one, more recently attempted than a real result, must never shadow
/// that result -- ELPAC policy is that the last *obtained* level stays in
/// effect until superseded, not "whatever was most recently attempted." When
/// a student has never once received a level, the most recent attempt is
/// still used for Academic Year/Test Purpose/Grade (so the review window
/// shows what was tried), but Overall Performance Level is left blank.
public enum ELPACLongitudinalReader {
    public static func read(contentsOf url: URL) throws -> Table {
        try flatten(try readGrid(contentsOf: url))
    }

    public static let outputHeaders = [
        "Student Name", "Student ID", "English Proficiency", "Academic Year",
        "Test Purpose", "Test Grade Level", "Overall Performance Level",
    ]

    // MARK: - Reading the raw grid

    /// Only true .xlsx is supported: the export seen so far arrives that way,
    /// and the block layout here depends on reading cells by position, which
    /// the other spreadsheet-ish formats this app reads were never built to
    /// preserve as reliably.
    static func readGrid(contentsOf url: URL) throws -> [[String]] {
        guard case .xlsx = try SourceFormat.detect(at: url) else {
            throw ConverterError(
                "This doesn't look like an ELPAC Longitudinal Roster export. "
                + "Export it from Illuminate as Excel (.xlsx) and try again.")
        }
        let archive = try ZipArchive(contentsOf: url)
        let sharedStrings = try XLSXReader.readSharedStrings(archive)
        let path = try XLSXReader.firstWorksheetPath(archive)
        return try XLSXReader.readSheet(archive, path: path, sharedStrings: sharedStrings)
    }

    // MARK: - Row classification

    /// Column indices, 0-based: C=2, H=7, N=13, P=15, R=17, S=18, Z=25.
    static let studentNameColumn = 2
    static let studentIDColumn = 7
    static let englishProficiencyColumn = 13
    static let testPurposeColumn = 15
    static let academicYearColumn = 17
    static let testGradeLevelColumn = 18
    static let overallPerformanceLevelColumn = 25

    enum RowKind: Equatable {
        case student(name: String, studentID: String, englishProficiency: String)
        case yearRow(
            testPurpose: String, academicYear: String, gradeLevel: String,
            overallPerformanceLevel: String)
        case other
    }

    static func classify(_ row: [String]) -> RowKind {
        let name = cell(row, studentNameColumn)
        let studentID = cell(row, studentIDColumn)
        if !name.isEmpty, isStudentID(studentID) {
            return .student(
                name: name, studentID: studentID,
                englishProficiency: cell(row, englishProficiencyColumn))
        }
        let academicYear = cell(row, academicYearColumn)
        if isAcademicYear(academicYear) {
            return .yearRow(
                testPurpose: cell(row, testPurposeColumn), academicYear: academicYear,
                gradeLevel: cell(row, testGradeLevelColumn),
                overallPerformanceLevel: cell(row, overallPerformanceLevelColumn))
        }
        return .other
    }

    static func isStudentID(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isNumber)
    }

    static func isAcademicYear(_ text: String) -> Bool {
        text.range(of: "^\\d{4}-\\d{2}$", options: .regularExpression) != nil
    }

    // MARK: - Flattening

    private struct YearRow {
        let testPurpose: String
        let academicYear: String
        let gradeLevel: String
        let overallPerformanceLevel: String
        let rowNumber: Int
    }

    private struct StudentBlock {
        let name: String
        let studentID: String
        let englishProficiency: String
        let headerRowNumber: Int
        var years: [YearRow] = []
    }

    static func flatten(_ grid: [[String]]) throws -> Table {
        var blocks: [StudentBlock] = []
        var current: StudentBlock?

        func closeCurrent() {
            if let block = current { blocks.append(block) }
            current = nil
        }

        for (index, row) in grid.enumerated() {
            let rowNumber = index + 1
            switch classify(row) {
            case .student(let name, let studentID, let englishProficiency):
                closeCurrent()
                current = StudentBlock(
                    name: name, studentID: studentID, englishProficiency: englishProficiency,
                    headerRowNumber: rowNumber)
            case .yearRow(let testPurpose, let academicYear, let gradeLevel, let overallLevel):
                current?.years.append(YearRow(
                    testPurpose: testPurpose, academicYear: academicYear, gradeLevel: gradeLevel,
                    overallPerformanceLevel: overallLevel, rowNumber: rowNumber))
            case .other:
                continue
            }
        }
        closeCurrent()

        guard !blocks.isEmpty else {
            throw ConverterError(
                "This doesn't look like an ELPAC Longitudinal Roster export: "
                + "no student rows were found.")
        }

        var rows: [[String: String]] = []
        var rowNumbers: [Int] = []
        for block in blocks {
            // When a real level exists, every displayed field comes from
            // that one row -- never a blend of "this year's attempt" with
            // "an older year's score," which would misrepresent which
            // administration actually produced the level being tagged.
            let valid = mostRecentYearWithALevel(block.years)
            let chosen = valid ?? mostRecentAttempt(block.years)
            rows.append([
                "Student Name": block.name,
                "Student ID": block.studentID,
                "English Proficiency": block.englishProficiency,
                "Academic Year": chosen?.academicYear ?? "",
                "Test Purpose": chosen?.testPurpose ?? "",
                "Test Grade Level": chosen?.gradeLevel ?? "",
                "Overall Performance Level": valid?.overallPerformanceLevel ?? "",
            ])
            rowNumbers.append(chosen?.rowNumber ?? block.headerRowNumber)
        }
        return Table(headers: outputHeaders, rows: rows, rowNumbers: rowNumbers)
    }

    /// Among years that produced a real Overall Performance Level, the one
    /// with the greatest Academic Year; when that year has both an Initial
    /// and a Summative row, the Summative one. `nil` when no year ever
    /// produced a level at all.
    private static func mostRecentYearWithALevel(_ years: [YearRow]) -> YearRow? {
        mostRecentAttempt(years.filter { !$0.overallPerformanceLevel.isEmpty })
    }

    /// The year row with the greatest Academic Year, regardless of whether
    /// it produced a score; when that year has both an Initial and a
    /// Summative row, the Summative one (it carries the real scores --
    /// Initial is a placeholder of dashes until then).
    private static func mostRecentAttempt(_ years: [YearRow]) -> YearRow? {
        guard !years.isEmpty else { return nil }
        let maxYear = years.compactMap { leadingYear($0.academicYear) }.max()
        let candidates = years.filter { leadingYear($0.academicYear) == maxYear }
        return candidates.first { $0.testPurpose.lowercased() == "summative" } ?? candidates.last
    }

    private static func leadingYear(_ academicYear: String) -> Int? {
        guard let match = academicYear.range(of: "^\\d{4}", options: .regularExpression) else {
            return nil
        }
        return Int(academicYear[match])
    }

    /// Trimmed text for a cell; a short row (the xlsx reader omits trailing
    /// empty cells) reads as blank rather than out of bounds.
    static func cell(_ row: [String], _ index: Int) -> String {
        (row.indices.contains(index) ? row[index] : "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
