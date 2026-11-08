import Foundation

/// Illuminate's "ELPAC Longitudinal Roster" export -> eduCLIMBER Tag Upload,
/// one tag per student based on their own current ELPI level.
///
/// Unlike a plain Tag Upload, there is no single tag name typed in for the
/// whole batch here: every student can land on a different ELPI level (e.g.
/// "1", "2L", "2H", "3H", "4") for the current Academic Year --
/// `ELPACLongitudinalReader` has already picked that year out of each
/// student's full testing history -- so the Tag Name is built per row,
/// appending that level to a prefix typed in once (e.g. "ELPI Level " +
/// "2H" -> "ELPI Level 2H"). A student with no current-year ELPI (no testing
/// history on file yet) has nothing to tag them with, so that row is flagged
/// rather than guessed at.
public struct ELPACLongitudinalRosterConverter: AssessmentConverter {
    /// Where the shared Student Roster lives. Injectable so tests can point
    /// at a temporary file instead of the real, shared Application Support
    /// location.
    private let rosterStoreURL: URL

    public init(rosterStoreURL: URL = StudentRosterStore.defaultStoreURL()) {
        self.rosterStoreURL = rosterStoreURL
    }

    public let key = "elpac_longitudinal_tag_upload"
    public let displayName = "ELPAC Longitudinal Roster (Tag Upload)"
    public let summary =
        "Builds an eduCLIMBER tag upload from an Illuminate ELPAC Longitudinal Roster export, "
        + "one tag per student based on their current Academic Year's ELPI level (e.g. \"ELPI "
        + "Level 2H\") -- not one tag typed in for the whole batch, since every student can land "
        + "on a different level. A student with no current-year ELPI is flagged rather than "
        + "guessed at. Student ID and name are deduplicated and backed by the shared Student "
        + "Roster, the same as every other converter here."

    public var prompts: [PromptField] {
        [
            PromptField(
                key: "school_year", label: "School Year",
                kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
                help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
                placeholder: "2026-2027", defaultValue: EurekaMathConverter.currentSchoolYear()),
            PromptField(
                key: "tag_name_prefix", label: "Tag Name Prefix", kind: .text(pattern: ".*"),
                help: "Each student's ELPI level is appended to this, e.g. \"ELPI Level 2H\".",
                placeholder: "ELPI Level ", defaultValue: "ELPI Level "),
            PromptField(
                key: "include_tag_flag", label: "Include Tag Flag Column?",
                kind: .choice(["No", "Yes"]), isRequired: false,
                help: "Most tag upload formats don't use a flag value -- leave this off unless "
                    + "yours does. An unanswered or missing value behaves the same as \"No\"."),
            PromptField(
                key: "tag_flag", label: "Tag Flag", kind: .text(pattern: ".*"),
                help: "Only used when \"Include Tag Flag Column?\" above is Yes.",
                placeholder: "Y", isRequired: false),
        ]
    }

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "student_id", label: "Student ID", example: "20212207"),
        SourceColumn(key: "student_name", label: "Student Name", example: "Abundis, Kataleah C."),
        SourceColumn(
            key: "elpi_level", label: "Overall Performance Level",
            aliases: ["ELPI", "ELPI Level"], example: "2H"),
    ]

    public let outputColumns = [
        "Student ID", "Student First Name", "Student Last Name",
        "School Year", "Tag Name", "Tag Flag",
    ]

    public func loadSource(at url: URL) throws -> Table {
        try ELPACLongitudinalReader.read(contentsOf: url)
    }

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

        let schoolYear = trimmed(answers["school_year"])
        let tagNamePrefix = trimmed(answers["tag_name_prefix"])
        let includeTagFlag = trimmed(answers["include_tag_flag"]).caseInsensitiveCompare("Yes")
            == .orderedSame
        let tagFlag = trimmed(answers["tag_flag"])

        // Best-effort fallback only -- a missing or unreadable roster file
        // just means no fixes are available yet, not a reason to stop.
        let roster = StudentRosterLookup((try? StudentRosterStore.load(from: rosterStoreURL)) ?? [])

        // Dropped from the export entirely when not requested, rather than
        // just left blank -- a column of nothing is still a column eduCLIMBER
        // has to be told to ignore.
        let outputCols = includeTagFlag ? outputColumns : outputColumns.filter { $0 != "Tag Flag" }
        var result = ConversionResult(columns: outputCols)
        var seenStudentIDs: Set<String> = []

        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let rawStudentID = table.value(row, header("student_id"))
            let studentName = table.value(row, header("student_name"))
            let elpiLevel = table.value(row, header("elpi_level"))

            // The reader already produces one block per student, but a
            // district export can still list the same student twice (e.g. a
            // transfer that shows up under two schools) -- only the first
            // occurrence is tagged, the same rule Tag Upload itself uses.
            if !rawStudentID.isEmpty {
                if seenStudentIDs.contains(rawStudentID) {
                    result.notices.append(RowError(
                        rowNumber: rowNumber,
                        message: "Student ID \(rawStudentID) — duplicate of an earlier row; "
                            + "this row was skipped."))
                    continue
                }
                seenStudentIDs.insert(rawStudentID)
            }

            var name = (first: "", last: "")
            if !studentName.isEmpty, studentName.contains(",") {
                name = RunningRecordsConverter.splitStudentName(studentName)
            }
            let filled = roster.fill(
                studentID: rawStudentID, firstName: name.first, lastName: name.last)
            let studentID = filled.studentID
            name = (first: filled.firstName, last: filled.lastName)

            var rowProblems: [String] = []
            if studentID.isEmpty { rowProblems.append("Student ID is blank.") }
            if studentName.isEmpty {
                if name.first.isEmpty && name.last.isEmpty {
                    rowProblems.append("Student Name is blank.")
                }
            } else if !studentName.contains(",") {
                rowProblems.append("Student Name '\(studentName)' is not in 'Last, First' format.")
            } else if name.first.isEmpty || name.last.isEmpty {
                rowProblems.append("Student Name '\(studentName)' is missing a first or last name.")
            }
            if elpiLevel.isEmpty {
                rowProblems.append(
                    "No current-year ELPI level on file -- this student has no Academic Year "
                    + "to tag yet.")
            }

            let label = studentName.isEmpty
                ? (studentID.isEmpty ? "" : "Student ID \(studentID)")
                : studentName
            let labelPrefix = label.isEmpty ? "" : "\(label) — "

            guard rowProblems.isEmpty else {
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: labelPrefix + problem))
                }
                continue
            }

            result.rows.append([
                "Student ID": studentID,
                "Student First Name": name.first,
                "Student Last Name": name.last,
                "School Year": schoolYear,
                "Tag Name": tagNamePrefix + elpiLevel,
                "Tag Flag": tagFlag,
            ])
        }
        return result
    }

    public var defaultFileNameTemplate: String { "eduCLIMBER_Upload_{assessment}_{date}_{time}" }

    public func defaultOutputName(answers: [String: String]) -> String {
        let tokens = FileNameTemplate.tokens(converter: self, answers: answers)
        return FileNameTemplate(defaultFileNameTemplate).render(tokens: tokens)
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
