import Foundation

/// Formative export (Social Studies benchmarks) -> eduCLIMBER Generic Assessment.
///
/// The export mixes real student rows in with rollup rows -- a Key row, a
/// Tags row, a Totals row, and a subtotal row per school/teacher/class --
/// none of which carry a Formative ID. Those are skipped without comment,
/// the same way a Topic Quiz row is skipped in the Eureka Math export. A
/// *real* student row can still have a blank email (Formative doesn't always
/// have one on file), so Formative ID -- not email -- is what distinguishes
/// a rollup row from a real one.
///
/// Formative's own "Student ID" column is Formative's internal id, not the
/// district's, so it's useless as eduCLIMBER's Student ID. The real Student
/// ID (and Grade) instead comes from a roster file the user builds for this
/// purpose, joined here by email address -- falling back to the persisted
/// FormativeIDMatchStore (managed in its own window) when Formative didn't
/// supply an email for this row at all.
///
/// A student the export shows as assigned but never submitted (no
/// Timestamp, no score) is flagged as a blocking problem -- there's nothing
/// to upload for them -- and also collected into a separate follow-up
/// report, since "go check on these students" is a different kind of task
/// than "fix a typo in the source file."
public struct FormativeConverter: AssessmentConverter {
    public static let assessmentGroup = "Social Studies Benchmarks"

    /// Where the Formative ID Matches window's saved matches live. Injectable
    /// so tests can point at a temporary file instead of the real, shared
    /// Application Support location.
    private let matchStoreURL: URL

    public init(matchStoreURL: URL = FormativeIDMatchStore.defaultStoreURL()) {
        self.matchStoreURL = matchStoreURL
    }

    public let key = "formative_social_studies_benchmark"
    public let displayName = "Social Studies Benchmark (Formative)"
    public let summary =
        "Formative export (Student ID, Timestamp, Email/username, Last name, First name, Total "
        + "score (%)). Rollup rows (Key, Tags, Totals, and school/teacher/class subtotals) are "
        + "skipped. Student ID and Grade come from a roster file joined by email, since "
        + "Formative's own Student ID isn't the district's; a row with no email falls back to "
        + "the Formative ID Matches window's saved matches. A student who hasn't submitted yet "
        + "is flagged and listed in a separate follow-up report."

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
        SourceColumn(key: "formative_id", label: "Student ID", example: "6aa35b06dfcecc915a66a9ba"),
        SourceColumn(key: "email", label: "Email/username", isRequired: false,
                     example: "student54@whittiercity.net"),
        SourceColumn(key: "last_name", label: "Last name", example: "Hernandez Zepeda"),
        SourceColumn(key: "first_name", label: "First name", example: "Agustin"),
        SourceColumn(
            key: "timestamp", label: "Timestamp", isRequired: false,
            example: "10/2/2026, 9:14:50 AM"),
        SourceColumn(key: "score_percent", label: "Total score (%)", example: "44"),
    ]

    /// The roster's own columns -- built by the user for this purpose, so
    /// Grade is expected already in eduCLIMBER's own form ("6", "K", "TK"),
    /// not an Aeries numeric code. "StuEmail" is the real header the actual
    /// roster uses; "Email" is kept too in case a future roster spells it
    /// plainly. First/Last Name are optional: the roster's version wins when
    /// present (Formative's own name sometimes arrives truncated, e.g. "G"
    /// instead of "Garcia"), falling back to Formative's name only when the
    /// roster doesn't have one.
    static let rosterColumns: [SourceColumn] = [
        SourceColumn(key: "email", label: "StuEmail", aliases: ["Email", "Student Email"],
                     example: "student54@whittiercity.net"),
        SourceColumn(key: "student_id", label: "Student ID", example: "20221371"),
        SourceColumn(key: "grade", label: "Grade", example: "6"),
        SourceColumn(key: "first_name", label: "First Name", isRequired: false, example: "Agustin"),
        SourceColumn(key: "last_name", label: "Last Name", isRequired: false, example: "Hernandez Zepeda"),
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
        let idMatches = Dictionary(
            try FormativeIDMatchStore.load(from: matchStoreURL).map { ($0.formativeID, $0.email) },
            uniquingKeysWith: { first, _ in first })

        var result = ConversionResult(columns: outputColumns)
        var notSubmitted: [[String: String]] = []

        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let formativeID = table.value(row, header("formative_id"))

            // Key, Tags, Totals, and the school/teacher/class subtotal rows
            // have no Formative ID -- they were never student data to begin
            // with. A real student row can still have a blank email, so
            // email itself is no longer what distinguishes a rollup row.
            guard !formativeID.isEmpty else { continue }

            var email = table.value(row, header("email"))
            var usedSavedMatch = false
            if email.isEmpty, let known = idMatches[formativeID] {
                email = known
                usedSavedMatch = true
            }

            let formativeLastName = table.value(row, header("last_name"))
            let formativeFirstName = table.value(row, header("first_name"))
            let timestamp = table.value(row, header("timestamp"))
            let percentText = table.value(row, header("score_percent"))

            // The roster is the more trustworthy name source -- Formative's
            // own Last/First name sometimes arrives truncated (e.g. "G"
            // instead of "Garcia"), while the roster is the district's own
            // student list -- so it wins whenever it has a name at all.
            let rosterMatch = email.isEmpty ? nil : roster[email.lowercased()]
            let rosterLastName = rosterMatch?.lastName ?? ""
            let rosterFirstName = rosterMatch?.firstName ?? ""
            let lastName = rosterLastName.isEmpty ? formativeLastName : rosterLastName
            let firstName = rosterFirstName.isEmpty ? formativeFirstName : rosterFirstName

            let name = [lastName, firstName].filter { !$0.isEmpty }.joined(separator: ", ")
            let label = !name.isEmpty ? name : (!email.isEmpty ? email : "Formative ID \(formativeID)")
            let labelPrefix = "\(label) — "

            guard !email.isEmpty else {
                result.errors.append(RowError(
                    rowNumber: rowNumber,
                    message: labelPrefix + "has no email in the export and no saved match -- "
                        + "add one in Window > Formative ID Matches."))
                continue
            }
            if usedSavedMatch {
                result.notices.append(RowError(
                    rowNumber: rowNumber, message: labelPrefix + "email filled in from a saved match."))
            }

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
            if let match = rosterMatch {
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

    // MARK: - Duplicate submissions

    /// Formative's own Student ID stays identical across copies of the same
    /// real submission (the same assignment pushed through two class
    /// rosters), so it's the right key for finding them -- unlike Email,
    /// which this converter otherwise treats as the student's identity, this
    /// id has nothing to do with the roster join and is only used here.
    public func duplicateGroups(in table: Table) -> [[Int]] {
        let idColumn = table.findColumn(["Student ID"])
        var order: [String] = []
        var byID: [String: [Int]] = [:]
        for (index, row) in table.rows.enumerated() {
            let id = table.value(row, idColumn)
            guard !id.isEmpty else { continue }
            if byID[id] == nil { order.append(id) }
            byID[id, default: []].append(index)
        }
        return order.compactMap { byID[$0] }.filter { $0.count > 1 }
    }

    public var duplicatePickerColumns: [String] {
        ["Class", "Teacher name", "Timestamp", "Total score (%)"]
    }

    public func duplicateGroupLabel(for table: Table, firstRowIndex: Int) -> String {
        let row = table.rows[firstRowIndex]
        let last = table.value(row, table.findColumn(["Last name"]))
        let first = table.value(row, table.findColumn(["First name"]))
        return [last, first].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: - The roster join

    struct RosterMatch {
        let studentID: String
        let grade: String
        let firstName: String
        let lastName: String
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
        let firstNameHeader = mapping.match(for: "first_name")?.header
        let lastNameHeader = mapping.match(for: "last_name")?.header

        var lookup: [String: RosterMatch] = [:]
        for row in rosterTable.rows {
            let email = rosterTable.value(row, emailHeader).lowercased()
            guard !email.isEmpty else { continue }
            lookup[email] = RosterMatch(
                studentID: rosterTable.value(row, idHeader),
                grade: rosterTable.value(row, gradeHeader),
                firstName: rosterTable.value(row, firstNameHeader),
                lastName: rosterTable.value(row, lastNameHeader))
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
