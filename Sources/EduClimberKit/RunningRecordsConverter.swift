import Foundation

/// Running Records → eduCLIMBER.
///
/// Source export columns: Student ("Last, First"), Student ID, Grade Level,
/// Reading Level (A-Z), Proficiency Level.
public struct RunningRecordsConverter: AssessmentConverter {
    public static let assessmentGroup = "Running Records"
    public static let assessmentName = "Independent Reading Level"
    public static let assessmentWindows = ["Trimester 1", "Trimester 2", "Trimester 3"]
    public static let schoolYearPattern = "^[0-9]{4}-[0-9]{4}$"

    public init() {}

    public let key = "running_records"
    public let displayName = "Running Records"
    public let summary =
        "Reading assessment export (Student, Student ID, Grade Level, "
        + "Reading Level (A-Z), Proficiency Level)."

    public let prompts: [PromptField] = [
        PromptField(
            key: "assessment_window",
            label: "Assessment Window",
            kind: .choice(RunningRecordsConverter.assessmentWindows)),
        PromptField(
            key: "school_year",
            label: "School Year",
            kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
            help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
            placeholder: "2026-2027"),
    ]

    // The name can arrive either way, so all three name columns are optional on
    // their own: a file needs the combined column OR the split pair, which
    // `problems(for:)` below enforces.
    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "student", label: "Student", aliases: ["Student Name"],
                     isRequired: false, example: "Gomez, Maria"),
        SourceColumn(key: "first_name", label: "First Name",
                     aliases: ["Given Name", "Student First Name"],
                     isRequired: false, example: "Maria"),
        SourceColumn(key: "last_name", label: "Last Name",
                     aliases: ["Surname", "Family Name", "Student Last Name"],
                     isRequired: false, example: "Gomez"),
        SourceColumn(key: "student_id", label: "Student ID",
                     aliases: ["Student Identifier", "Student Number"], example: "100234"),
        SourceColumn(key: "grade", label: "Grade Level", aliases: ["Grade"],
                     example: "K, 1, 2 ... 8"),
        SourceColumn(key: "reading_level", label: "Reading Level (A-Z)",
                     aliases: ["Reading Level", "Independent Reading Level"],
                     example: "Below A, A ... Z"),
        SourceColumn(key: "proficiency", label: "Proficiency Level", aliases: ["Proficiency"],
                     example: "At Standard"),
    ]

    /// The 15 eduCLIMBER columns, in the order the import expects.
    public let outputColumns = [
        "Assessment Group",
        "Assessment Name",
        "Assessment Window",
        "School Year",
        "Student ID",
        "Student First Name",
        "Student Middle Initial",
        "Student Last Name",
        "Date of Birth",
        "Student Grade Level",
        "Score Detail 2",
        "Reading Level",
        "Score Detail 1",
        "Proficiency Level",
        "Score",
    ]

    /// A file must carry the student name one way or the other.
    public func problems(for mapping: ColumnMapping) -> [String] {
        let combined = mapping.match(for: "student")?.header != nil
        let split = mapping.match(for: "first_name")?.header != nil
            && mapping.match(for: "last_name")?.header != nil
        if combined || split { return [] }
        return [Self.missingNameColumnsMessage]
    }

    static let missingNameColumnsMessage =
        "This file needs the student name: either a 'Student' column in "
        + "'Last, First' form, or separate 'First Name' and 'Last Name' columns."

    public func convert(
        table: Table, answers: [String: String], columns: [String: String?]
    ) throws -> ConversionResult {
        let window = trimmed(answers["assessment_window"])
        let schoolYear = trimmed(answers["school_year"])

        func header(_ key: String) -> String? {
            guard let value = columns[key] else { return nil }
            return value
        }

        let missing = sourceColumns
            .filter { $0.isRequired && (header($0.key) ?? "").isEmpty }
            .map(\.label)
        if !missing.isEmpty {
            let found = table.headers.isEmpty ? "(none)" : table.headers.joined(separator: ", ")
            throw ConverterError(
                "No column chosen for: \(missing.joined(separator: ", "))."
                + "\nColumns found in this file: \(found)")
        }

        let combinedHeader = header("student")
        let firstHeader = header("first_name")
        let lastHeader = header("last_name")
        // Prefer columns that are already split -- no parsing, nothing to guess.
        let useSplitNames = firstHeader != nil && lastHeader != nil
        guard useSplitNames || combinedHeader != nil else {
            let found = table.headers.isEmpty ? "(none)" : table.headers.joined(separator: ", ")
            throw ConverterError(
                Self.missingNameColumnsMessage + "\nColumns found in this file: \(found)")
        }
        guard !table.rows.isEmpty else {
            throw ConverterError("The source file has a header row but no student rows.")
        }

        var result = ConversionResult(columns: outputColumns)
        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let student = table.value(row, header("student"))
            let studentID = table.value(row, header("student_id"))
            let grade = table.value(row, header("grade"))
            let readingLevel = table.value(row, header("reading_level"))
            let proficiency = table.value(row, header("proficiency"))

            var rowProblems: [String] = []
            var name = (first: "", last: "")

            let splitFirst = table.value(row, firstHeader)
            let splitLast = table.value(row, lastHeader)
            if useSplitNames && !(splitFirst.isEmpty && splitLast.isEmpty) {
                // Already split by the source system: use the values as they are.
                name = (first: splitFirst, last: splitLast)
                if splitFirst.isEmpty { rowProblems.append("First Name is blank.") }
                if splitLast.isEmpty { rowProblems.append("Last Name is blank.") }
            } else if !student.isEmpty {
                // One combined column: "Last, First".
                name = Self.splitStudentName(student)
                if !student.contains(",") {
                    rowProblems.append("Student name '\(student)' is not in 'Last, First' format.")
                } else if name.first.isEmpty || name.last.isEmpty {
                    rowProblems.append("Student name '\(student)' is missing a first or last name.")
                }
            } else {
                rowProblems.append("Student name is blank.")
            }
            if studentID.isEmpty {
                rowProblems.append("Student ID is blank.")
            }

            let score = ReadingLevels.score(for: readingLevel)
            if score == nil {
                if readingLevel.isEmpty {
                    rowProblems.append("Reading Level (A-Z) is blank.")
                } else {
                    rowProblems.append(
                        "Reading Level '\(readingLevel)' is not in the reading level table.")
                }
            }

            guard rowProblems.isEmpty, let score else {
                var label = student
                if label.isEmpty && !(name.first.isEmpty && name.last.isEmpty) {
                    label = [name.last, name.first].filter { !$0.isEmpty }.joined(separator: ", ")
                }
                if label.isEmpty && !studentID.isEmpty { label = "Student ID \(studentID)" }
                let prefix = label.isEmpty ? "" : "\(label) — "
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: prefix + problem))
                }
                continue
            }

            // Annotated so the type-checker does not have to solve a 15-entry
            // literal from context.
            let output: [String: String] = [
                "Assessment Group": Self.assessmentGroup,
                "Assessment Name": Self.assessmentName,
                "Assessment Window": window,
                "School Year": schoolYear,
                "Student ID": studentID,
                "Student First Name": name.first,
                "Student Middle Initial": "",
                "Student Last Name": name.last,
                "Date of Birth": "",
                "Student Grade Level": grade,
                // Score Detail 2 / Reading Level and Score Detail 1 / Proficiency
                // Level are deliberate duplicates: the eduCLIMBER import format
                // wants the same value in both columns.
                "Score Detail 2": readingLevel,
                "Reading Level": readingLevel,
                "Score Detail 1": proficiency,
                "Proficiency Level": proficiency,
                "Score": String(score),
            ]
            result.rows.append(output)
        }
        return result
    }

    public func defaultOutputName(answers: [String: String]) -> String {
        let window = trimmed(answers["assessment_window"]).replacingOccurrences(of: " ", with: "")
        let schoolYear = trimmed(answers["school_year"])
        let parts = ["Running_Records", window, schoolYear, "educlimber"].filter { !$0.isEmpty }
        return parts.joined(separator: "_") + ".csv"
    }

    /// Split "Last, First" into its parts. An extra comma ("Last, First, Jr")
    /// keeps everything after the first comma as the first-name text.
    public static func splitStudentName(_ raw: String) -> (first: String, last: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = text.firstIndex(of: ",") else { return ("", "") }
        let last = String(text[text.startIndex..<comma])
        let first = String(text[text.index(after: comma)...])
        return (
            first.trimmingCharacters(in: .whitespacesAndNewlines),
            last.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
