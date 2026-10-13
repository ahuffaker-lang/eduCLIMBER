import Foundation

/// Formative export (Social Studies benchmarks) -> eduCLIMBER Generic Assessment.
///
/// The export mixes real student rows in with rollup rows -- a Key row, a
/// Tags row, a Totals row, and a subtotal row per school/teacher/class --
/// none of which carry an email address. Those are skipped without comment,
/// the same way a Topic Quiz row is skipped in the Eureka Math export.
///
/// Formative's own "Student ID" column is Formative's internal id, not the
/// district's, so it's useless as eduCLIMBER's Student ID. The real Student
/// ID (and Grade) instead comes from a roster file the user builds for this
/// purpose, joined here by email address.
///
/// A student the export shows as assigned but never submitted (no
/// Timestamp, no score) is flagged as a blocking problem -- there's nothing
/// to upload for them -- and also collected into a separate follow-up
/// report, since "go check on these students" is a different kind of task
/// than "fix a typo in the source file."
public struct FormativeConverter: AssessmentConverter {
    public static let assessmentGroup = "Social Studies Benchmarks"

    public init() {}

    public let key = "formative_social_studies_benchmark"
    public let displayName = "Social Studies Benchmark (Formative)"
    public let summary =
        "Formative export (Timestamp, Email/username, Last name, First name, Total score (%)). "
        + "Rollup rows (Key, Tags, Totals, and school/teacher/class subtotals) are skipped. "
        + "Student ID and Grade come from a roster file joined by email, since Formative's own "
        + "Student ID isn't the district's. A student who hasn't submitted yet is flagged and "
        + "listed in a separate follow-up report."

    public var prompts: [PromptField] {
        [
            PromptField(
                key: "assessment_name", label: "Assessment Name", kind: .text(pattern: ".*"),
                help: "e.g. Benchmark 1: Origins of Civilization.",
                placeholder: "Benchmark 1: Origins of Civilization"),
            PromptField(
                key: "assessment_window", label: "Assessment Window",
                kind: .choice(["Test 1", "Test 2", "Test 3"])),
            PromptField(
                key: "school_year", label: "School Year",
                kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
                help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
                placeholder: "2026-2027", defaultValue: EurekaMathConverter.currentSchoolYear()),
            PromptField(
                key: "roster_file", label: "Student Roster File", kind: .file,
                help: "A file with Email, Student ID, and Grade for each student."),
        ]
    }

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "email", label: "Email/username", example: "student54@whittiercity.net"),
        SourceColumn(key: "last_name", label: "Last name", example: "Hernandez Zepeda"),
        SourceColumn(key: "first_name", label: "First name", example: "Agustin"),
        SourceColumn(
            key: "timestamp", label: "Timestamp", isRequired: false,
            example: "10/2/2026, 9:14:50 AM"),
        SourceColumn(key: "score_percent", label: "Total score (%)", example: "44"),
    ]

    /// The roster's own columns -- built by the user for this purpose, so
    /// Grade is expected already in eduCLIMBER's own form ("6", "K", "TK"),
    /// not an Aeries numeric code.
    static let rosterColumns: [SourceColumn] = [
        SourceColumn(key: "email", label: "Email", example: "student54@whittiercity.net"),
        SourceColumn(key: "student_id", label: "Student ID", example: "20221371"),
        SourceColumn(key: "grade", label: "Grade", example: "6"),
    ]

    public let outputColumns = [
        "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
        "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
        "Date of Birth", "Student Grade Level", "Score",
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

        let assessmentName = trimmed(answers["assessment_name"])
        let assessmentWindow = trimmed(answers["assessment_window"])
        let schoolYear = trimmed(answers["school_year"])
        let roster = try Self.loadRoster(path: trimmed(answers["roster_file"]))

        var result = ConversionResult(columns: outputColumns)
        var notSubmitted: [[String: String]] = []

        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let email = table.value(row, header("email"))

            // Key, Tags, Totals, and the school/teacher/class subtotal rows
            // have no email -- they were never student data to begin with.
            guard !email.isEmpty else { continue }

            let lastName = table.value(row, header("last_name"))
            let firstName = table.value(row, header("first_name"))
            let timestamp = table.value(row, header("timestamp"))
            let percentText = table.value(row, header("score_percent"))

            let name = [lastName, firstName].filter { !$0.isEmpty }.joined(separator: ", ")
            let labelPrefix = "\(name.isEmpty ? email : name) — "

            guard !timestamp.isEmpty else {
                result.errors.append(
                    RowError(rowNumber: rowNumber, message: labelPrefix + "has not yet submitted this assessment."))
                notSubmitted.append([
                    "Student Name": name.isEmpty ? email : name,
                    "Email": email,
                ])
                continue
            }

            var rowProblems: [String] = []
            if lastName.isEmpty { rowProblems.append("Last name is blank.") }
            if firstName.isEmpty { rowProblems.append("First name is blank.") }

            var score = 0
            if let percentValue = Double(percentText) {
                score = Int(percentValue.rounded())
            } else {
                rowProblems.append("Total score (%) '\(percentText)' is not a number.")
            }

            var studentID = ""
            var grade = ""
            if let match = roster[email.lowercased()] {
                studentID = match.studentID
                grade = match.grade
                if studentID.isEmpty { rowProblems.append("Roster entry for \(email) has a blank Student ID.") }
                if grade.isEmpty { rowProblems.append("Roster entry for \(email) has a blank Grade.") }
            } else {
                rowProblems.append("Email \(email) was not found in the roster file.")
            }

            guard rowProblems.isEmpty else {
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: labelPrefix + problem))
                }
                continue
            }

            result.rows.append([
                "Assessment Group": Self.assessmentGroup,
                "Assessment Name": assessmentName,
                "Assessment Window": assessmentWindow,
                "School Year": schoolYear,
                "Student ID": studentID,
                "Student First Name": firstName,
                "Student Middle Initial": "",
                "Student Last Name": lastName,
                "Date of Birth": "",
                "Student Grade Level": grade,
                "Score": String(score),
            ])
        }

        if !notSubmitted.isEmpty {
            result.followUpReport = FollowUpReport(
                title: "Not Yet Submitted", columns: ["Student Name", "Email"], rows: notSubmitted)
        }
        return result
    }

    // MARK: - The roster join

    struct RosterMatch {
        let studentID: String
        let grade: String
    }

    static func loadRoster(path: String) throws -> [String: RosterMatch] {
        let url = URL(fileURLWithPath: path)
        let rosterTable: Table
        do {
            rosterTable = try Pipeline.loadSource(at: url)
        } catch {
            throw ConverterError("Could not read the roster file: \(error.localizedDescription)")
        }
        let mapping = resolveColumns(table: rosterTable, columns: rosterColumns)
        guard !mapping.needsConfirmation, mapping.problems().isEmpty else {
            throw ConverterError(
                "The roster file's columns could not be matched automatically.\n"
                + mapping.unmatchedMessage())
        }
        let emailHeader = mapping.match(for: "email")?.header
        let idHeader = mapping.match(for: "student_id")?.header
        let gradeHeader = mapping.match(for: "grade")?.header

        var lookup: [String: RosterMatch] = [:]
        for row in rosterTable.rows {
            let email = rosterTable.value(row, emailHeader).lowercased()
            guard !email.isEmpty else { continue }
            lookup[email] = RosterMatch(
                studentID: rosterTable.value(row, idHeader),
                grade: rosterTable.value(row, gradeHeader))
        }
        return lookup
    }

    public var defaultFileNameTemplate: String {
        "{assessment}_{source}_{date}_educlimber"
    }

    public func defaultOutputName(answers: [String: String]) -> String {
        let tokens = FileNameTemplate.tokens(converter: self, answers: answers)
        return FileNameTemplate(defaultFileNameTemplate).render(tokens: tokens)
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
