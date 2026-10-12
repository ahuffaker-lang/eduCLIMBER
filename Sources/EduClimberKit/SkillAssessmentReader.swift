import Foundation

/// Reads a Renaissance/Illuminate "Skill Assessment Student List" export (the
/// `SkillAssessmentStudentListMainF` sheet) into a flat `Table`, one row per
/// student, with the owning teacher and the assessment's own name carried as
/// extra columns.
///
/// The source isn't a table in the usual sense: it's one block per teacher
/// (a Title row, an Assessment row, a Header row, then that teacher's Student
/// rows, then a Footer), and a class that runs past a printed page repeats
/// that block mid-roster rather than starting a new one. This reader doesn't
/// try to detect or remove that repeated block -- that reconstruction is only
/// needed to produce an exact-copy report for a single teacher, which this
/// app doesn't build. Instead it just keeps attributing Student rows to
/// whichever teacher the most recent Assessment row named, so a repeated
/// block for the same teacher is a harmless no-op rather than something that
/// has to be cleaned up first.
public enum SkillAssessmentReader {
    public static func read(contentsOf url: URL) throws -> Table {
        try flatten(try readGrid(contentsOf: url))
    }

    public static let outputHeaders = [
        "Teacher", "Student Name", "Student ID", "Total Attempts", "Last Assessed",
        "Number Correct", "Number Incorrect", "Number Answered", "Number Possible",
        "Percent Earned", "Correct Questions", "Assessment Name",
    ]

    // MARK: - Reading the raw grid

    /// Only true .xlsx is supported: every real export seen so far arrives that
    /// way, and the block layout here depends on reading cells by position,
    /// which the other spreadsheet-ish formats this app reads were never
    /// built to preserve as reliably.
    static func readGrid(contentsOf url: URL) throws -> [[String]] {
        guard case .xlsx = try SourceFormat.detect(at: url) else {
            throw ConverterError(
                "This doesn't look like a Skill Assessment Student List export. "
                + "Export it from Illuminate as Excel (.xlsx) and try again.")
        }
        let archive = try ZipArchive(contentsOf: url)
        let sharedStrings = try XLSXReader.readSharedStrings(archive)
        let path = try XLSXReader.firstWorksheetPath(archive)
        return try XLSXReader.readSheet(archive, path: path, sharedStrings: sharedStrings)
    }

    // MARK: - Row classification

    enum RowKind: Equatable {
        case assessment(name: String, teacher: String)
        case header
        case student
        case other
    }

    /// Column letters, 0-based: A=0 … Q=16.
    static func classify(_ row: [String]) -> RowKind {
        let a = cell(row, 0)
        let b = cell(row, 1)
        let d = rawCell(row, 3)
        let o = cell(row, 14)

        if a.hasPrefix("Assessment:") {
            let lines = d.components(separatedBy: "\n")
            let name = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let teacher = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
            return .assessment(name: name, teacher: teacher)
        }
        if a == "Student" { return .header }
        if isStudentRowNumber(a) { return .student }
        if b.hasPrefix("Generated on") || o.hasPrefix("Page ") { return .other }
        return .other
    }

    static func isStudentRowNumber(_ text: String) -> Bool {
        guard !text.isEmpty, text.hasSuffix(".") else { return false }
        return text.dropLast().allSatisfy(\.isNumber) && text.count > 1
    }

    // MARK: - Header validation

    /// Expected text at each column of the Header row. Columns B, D, G that the
    /// real export leaves blank (merged into a neighbor) aren't checked.
    static let expectedHeaderCells: [(column: Int, text: String)] = [
        (0, "Student"), (4, "ID"), (5, "Total Attempts"), (7, "Last Assessed"),
        (8, "# Correct"), (9, "# Incorrect"), (10, "# Answered"), (11, "# Possible"),
        (12, "% Earned"), (13, "Correct Questions"),
    ]

    static func validateHeader(_ row: [String]) throws {
        var mismatches: [String] = []
        for (column, expected) in expectedHeaderCells {
            let actual = rawCell(row, column)
            guard normalizedHeaderText(actual) == normalizedHeaderText(expected) else {
                let letter = columnLetter(column)
                mismatches.append("  column \(letter): expected \"\(expected)\", found \"\(actual)\"")
                continue
            }
        }
        guard mismatches.isEmpty else {
            throw ConverterError(
                "This file's header row doesn't match the Skill Assessment Student List "
                + "format this converter expects:\n" + mismatches.joined(separator: "\n")
                + "\n\nA different skill assessment may use different columns; "
                + "check the export before trying again.")
        }
    }

    static func normalizedHeaderText(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func columnLetter(_ index: Int) -> String {
        String(UnicodeScalar(UInt8(65 + index)))
    }

    // MARK: - Flattening

    static func flatten(_ grid: [[String]]) throws -> Table {
        var currentTeacher = ""
        var assessmentName = ""
        var sawHeader = false
        var rows: [[String: String]] = []
        var rowNumbers: [Int] = []

        for (index, row) in grid.enumerated() {
            switch classify(row) {
            case .assessment(let name, let teacher):
                if assessmentName.isEmpty, !name.isEmpty { assessmentName = name }
                currentTeacher = teacher
            case .header:
                if !sawHeader {
                    try validateHeader(row)
                    sawHeader = true
                }
            case .student:
                guard sawHeader else { continue }
                rows.append([
                    "Teacher": currentTeacher,
                    "Student Name": cell(row, 2),
                    "Student ID": cell(row, 4),
                    "Total Attempts": cell(row, 5),
                    "Last Assessed": cell(row, 7),
                    "Number Correct": cell(row, 8),
                    "Number Incorrect": cell(row, 9),
                    "Number Answered": cell(row, 10),
                    "Number Possible": cell(row, 11),
                    "Percent Earned": cell(row, 12),
                    "Correct Questions": rawCell(row, 13),
                    "Assessment Name": assessmentName,
                ])
                rowNumbers.append(index + 1)
            case .other:
                continue
            }
        }

        guard sawHeader else {
            throw ConverterError(
                "This doesn't look like a Skill Assessment Student List export: "
                + "no \"Student\" header row was found.")
        }
        guard !rows.isEmpty else {
            throw ConverterError("No student rows were found in this file.")
        }
        return Table(headers: outputHeaders, rows: rows, rowNumbers: rowNumbers)
    }

    /// Trimmed, whitespace-collapsed-at-the-edges text for a cell that should
    /// never itself contain meaningful line breaks (every student-row field
    /// except the ones read with `rawCell`).
    static func cell(_ row: [String], _ index: Int) -> String {
        rawCell(row, index).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The cell's text exactly as stored, only guarding against a short row
    /// (Excel/the xlsx reader omit trailing empty cells).
    static func rawCell(_ row: [String], _ index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }
}
