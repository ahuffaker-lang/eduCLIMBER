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

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "student", label: "Student", aliases: ["Student Name"],
                     example: "Gomez, Maria"),
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
            let name = Self.splitStudentName(student)

            if student.isEmpty {
                rowProblems.append("Student name is blank.")
            } else if !student.contains(",") {
                rowProblems.append("Student name '\(student)' is not in 'Last, First' format.")
            } else if name.first.isEmpty || name.last.isEmpty {
                rowProblems.append("Student name '\(student)' is missing a first or last name.")
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
                let label = student.isEmpty
                    ? (studentID.isEmpty ? "" : "Student ID \(studentID)")
                    : student
                let prefix = label.isEmpty ? "" : "\(label) — "
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: prefix + problem))
                }
                continue
            }

            result.rows.append([
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
            ])
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
