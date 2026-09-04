import Foundation

/// High Frequency Words → eduCLIMBER.
///
/// Source export columns: Assessment (e.g. "25-26 Gr 1 HFW Admin #1"), Student
/// Id, First Name, Last Name, Grade Level, % Correct, Performance Band,
/// Performance Band Level. Unlike Running Records, a single file mixes rows
/// from all three administrations of the year -- the Assessment column
/// carries the school year and administration for each row individually, so
/// there is nothing to ask the user; it is parsed per row instead.
public struct HFWConverter: AssessmentConverter {
    public static let assessmentGroup = "High Frequency Words"
    public static let assessmentName = "HFW"

    public init() {}

    public let key = "hfw"
    public let displayName = "HFW"
    public let summary =
        "High Frequency Words assessment export (Assessment, Student Id, First Name, "
        + "Last Name, Grade Level, % Correct, Performance Band, Performance Band Level)."

    /// Nothing to ask: the Assessment column supplies the school year and
    /// administration for every row on its own.
    public let prompts: [PromptField] = []

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "assessment", label: "Assessment",
                     example: "25-26 Gr 1 HFW Admin #1"),
        SourceColumn(key: "student_id", label: "Student Id", aliases: ["Student ID"],
                     example: "2021xxx"),
        SourceColumn(key: "first_name", label: "First Name", example: "Joe"),
        SourceColumn(key: "last_name", label: "Last Name", example: "Smith"),
        SourceColumn(key: "grade", label: "Grade Level", aliases: ["Grade"],
                     example: "2nd Grade"),
        SourceColumn(key: "percent_correct", label: "% Correct", aliases: ["Percent Correct"],
                     example: "19.77%"),
        SourceColumn(key: "performance_band", label: "Performance Band",
                     example: "Below Basic"),
        SourceColumn(key: "performance_band_level", label: "Performance Band Level",
                     aliases: ["Band Level"], example: "2"),
    ]

    /// The 13 eduCLIMBER columns, in the order the import expects.
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
        "Score Detail 2 Performance Band",
        "Score Detail 1 Percent Correct",
        "Score",
    ]

    public func convert(
        table: Table, answers: [String: String], columns: [String: String?]
    ) throws -> ConversionResult {
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
            let assessment = table.value(row, header("assessment"))
            let studentID = table.value(row, header("student_id"))
            let firstName = table.value(row, header("first_name"))
            let lastName = table.value(row, header("last_name"))
            let rawGrade = table.value(row, header("grade"))
            let percentCorrect = table.value(row, header("percent_correct"))
            let performanceBand = table.value(row, header("performance_band"))
            let performanceBandLevel = table.value(row, header("performance_band_level"))

            var rowProblems: [String] = []

            if studentID.isEmpty { rowProblems.append("Student Id is blank.") }
            if firstName.isEmpty { rowProblems.append("First Name is blank.") }
            if lastName.isEmpty { rowProblems.append("Last Name is blank.") }

            let grade = Self.normalizeGrade(rawGrade)
            if grade == nil {
                rowProblems.append(
                    rawGrade.isEmpty
                        ? "Grade Level is blank."
                        : "Grade Level '\(rawGrade)' is not recognized.")
            }

            let parsed = Self.parseAssessment(assessment)
            if parsed == nil {
                rowProblems.append(
                    assessment.isEmpty
                        ? "Assessment is blank."
                        : "Assessment '\(assessment)' is not in the expected "
                            + "'YY-YY Gr <grade> HFW Admin #<n>' format.")
            }

            if percentCorrect.isEmpty { rowProblems.append("% Correct is blank.") }
            if performanceBand.isEmpty { rowProblems.append("Performance Band is blank.") }
            if performanceBandLevel.isEmpty {
                rowProblems.append("Performance Band Level is blank.")
            } else if Double(performanceBandLevel) == nil {
                rowProblems.append(
                    "Performance Band Level '\(performanceBandLevel)' is not a number.")
            }

            var label = [lastName, firstName].filter { !$0.isEmpty }.joined(separator: ", ")
            if label.isEmpty && !studentID.isEmpty { label = "Student ID \(studentID)" }
            let labelPrefix = label.isEmpty ? "" : "\(label) — "

            guard rowProblems.isEmpty, let grade, let parsed else {
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: labelPrefix + problem))
                }
                continue
            }

            // Annotated so the type-checker does not have to solve a 13-entry
            // literal from context.
            let output: [String: String] = [
                "Assessment Group": Self.assessmentGroup,
                "Assessment Name": Self.assessmentName,
                "Assessment Window": parsed.window,
                "School Year": parsed.schoolYear,
                "Student ID": studentID,
                "Student First Name": firstName,
                "Student Middle Initial": "",
                "Student Last Name": lastName,
                "Date of Birth": "",
                "Student Grade Level": grade,
                "Score Detail 2 Performance Band": performanceBand,
                "Score Detail 1 Percent Correct": percentCorrect,
                "Score": performanceBandLevel,
            ]
            result.rows.append(output)
        }
        return result
    }

    /// "2nd Grade" / "Grade 2" -> "2"; "Kindergarten" / "K" -> "K".
    static func normalizeGrade(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "k" || lower.contains("kinder") { return "K" }
        if let range = trimmed.range(of: #"\d+"#, options: .regularExpression) {
            return String(trimmed[range])
        }
        return nil
    }

    /// "25-26 Gr 1 HFW Admin #1" -> school year "2025-2026", window
    /// "Administration 1". The grade code between "Gr" and "HFW" is not used
    /// here -- it names which grade's version of the test was given, not the
    /// student's own grade, which comes from the Grade Level column instead.
    static func parseAssessment(_ raw: String) -> (schoolYear: String, window: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let regex = try? NSRegularExpression(
            pattern: #"^(\d{2})-(\d{2})\s+Gr\s+\S+\s+HFW\s+Admin\s*#\s*(\d+)$"#,
            options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { return nil }

        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: trimmed) else { return nil }
            return String(trimmed[r])
        }
        guard let startYY = group(1), let endYY = group(2), let admin = group(3) else { return nil }
        return (schoolYear: "20\(startYY)-20\(endYY)", window: "Administration \(admin)")
    }

    /// No shared window or year to key the name on -- a file mixes all three
    /// administrations -- so the name leans on the source file's own name and
    /// today's date instead.
    public var defaultFileNameTemplate: String {
        "{assessment}_{source}_{date}_educlimber"
    }

    public func defaultOutputName(answers: [String: String]) -> String {
        let tokens = FileNameTemplate.tokens(converter: self, answers: answers)
        return FileNameTemplate(defaultFileNameTemplate).render(tokens: tokens)
    }
}
