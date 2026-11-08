import Foundation

/// Any student list → eduCLIMBER tag upload.
///
/// Unlike every other converter here, the source file isn't one fixed export:
/// it's whatever list of students the user happens to be tagging this time,
/// built fresh for the purpose and never shaped the same way twice. The only
/// promise is that it has a Student ID and a name somewhere in it -- under
/// whatever headers that particular file uses -- so those are matched the
/// same loose, alias-and-similarity way every other converter's columns are,
/// rather than assumed to have fixed names. The name can arrive either way,
/// the same ambiguity Running Records handles: an Aeries "Print Query to
/// Excel" export, for instance, has one combined "Student Name" column
/// ("Last, First"), not separate first/last columns. The same kind of query
/// can also list one student more than once (e.g. separate rows per
/// enrollment segment) even though a tag upload only wants the student
/// tagged once, so rows are deduplicated by Student ID -- first row for a
/// given ID wins, later ones are dropped with a notice rather than exported
/// again. School Year, Tag Name, and Tag Flag are not in the source file at
/// all -- they describe the batch as a whole, so they're typed in once and
/// stamped onto every row. Tag Flag is the one eduCLIMBER tag-upload column
/// not every district format actually uses, so whether it's in the export at
/// all is its own prompt -- off by default, since most districts don't use
/// it -- rather than just leaving the value blank (a column full of nothing
/// still has to be dealt with on the eduCLIMBER side).
public struct TagUploadConverter: AssessmentConverter {
    /// Where the shared Student Roster lives. Injectable so tests can point
    /// at a temporary file instead of the real, shared Application Support
    /// location.
    private let rosterStoreURL: URL

    public init(rosterStoreURL: URL = StudentRosterStore.defaultStoreURL()) {
        self.rosterStoreURL = rosterStoreURL
    }

    public let key = "tag_upload"
    public let displayName = "Tag Upload"
    public let summary =
        "Builds an eduCLIMBER tag upload (Student ID, Student First Name, Student Last Name, "
        + "School Year, Tag Name, Tag Flag) from any file that has a Student ID and a name -- "
        + "either a combined 'Student Name' column ('Last, First') or separate first/last name "
        + "columns -- whatever else it contains, and whatever those columns are called. Rows "
        + "repeating the same Student ID are deduplicated, keeping the first. School Year and "
        + "Tag Name are typed in once for the whole batch; Tag Flag is off by default and can "
        + "be turned on for a tag format that uses one."

    public var prompts: [PromptField] {
        [
            PromptField(
                key: "school_year", label: "School Year",
                kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
                help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
                placeholder: "2026-2027", defaultValue: EurekaMathConverter.currentSchoolYear()),
            PromptField(
                key: "tag_name", label: "Tag Name", kind: .text(pattern: ".*"),
                help: "The exact tag name as it should appear in eduCLIMBER.",
                placeholder: "Special Education"),
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
        SourceColumn(
            key: "student_id", label: "Student ID",
            aliases: ["ID", "StudentID", "Student Identifier", "Student Number"],
            example: "20212318"),
        // The name can arrive either way, so all three are individually
        // optional: a file needs the combined column OR the split pair,
        // which `problems(for:)` below enforces.
        SourceColumn(
            key: "student", label: "Student Name", aliases: ["Student", "Name"],
            isRequired: false, example: "Garcia, Ethan"),
        SourceColumn(
            key: "first_name", label: "Student First Name",
            aliases: ["First Name", "FirstName", "Given Name"],
            isRequired: false, example: "Ethan"),
        SourceColumn(
            key: "last_name", label: "Student Last Name",
            aliases: ["Last Name", "LastName", "Surname", "Family Name"],
            isRequired: false, example: "Garcia"),
    ]

    public let outputColumns = [
        "Student ID", "Student First Name", "Student Last Name",
        "School Year", "Tag Name", "Tag Flag",
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
        "This file needs the student name: either a 'Student Name' column in "
        + "'Last, First' form, or separate 'Student First Name' and 'Student Last Name' columns."

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

        let schoolYear = trimmed(answers["school_year"])
        let tagName = trimmed(answers["tag_name"])
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

            // A query that lists one enrollment segment per row can repeat the
            // same student; a tag upload only wants them tagged once. The
            // first row for a given ID wins, matching whichever row happened
            // to come first in the source sheet. A blank ID isn't a real key,
            // so blank rows are never considered duplicates of each other --
            // each is its own "Student ID is blank" problem below.
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

            let student = table.value(row, combinedHeader)

            var rowProblems: [String] = []
            var firstName = ""
            var lastName = ""

            let splitFirst = table.value(row, firstHeader)
            let splitLast = table.value(row, lastHeader)
            if useSplitNames && !(splitFirst.isEmpty && splitLast.isEmpty) {
                // Already split by the source system: use the values as they are.
                firstName = splitFirst
                lastName = splitLast
            } else if !student.isEmpty {
                // One combined column: "Last, First".
                let name = RunningRecordsConverter.splitStudentName(student)
                firstName = name.first
                lastName = name.last
            }

            // A row with no usable name can still have a Student ID -- the
            // Student Roster's fallback for exactly that, remembered from
            // fixing the same gap on an earlier file.
            let filled = roster.fill(studentID: rawStudentID, firstName: firstName, lastName: lastName)
            let studentID = filled.studentID
            firstName = filled.firstName
            lastName = filled.lastName

            if useSplitNames && !(splitFirst.isEmpty && splitLast.isEmpty) {
                if firstName.isEmpty { rowProblems.append("Student First Name is blank.") }
                if lastName.isEmpty { rowProblems.append("Student Last Name is blank.") }
            } else if !student.isEmpty {
                if firstName.isEmpty || lastName.isEmpty {
                    rowProblems.append(
                        student.contains(",")
                            ? "Student Name '\(student)' is missing a first or last name."
                            : "Student Name '\(student)' is not in 'Last, First' format.")
                }
            } else if firstName.isEmpty && lastName.isEmpty {
                rowProblems.append("Student name is blank.")
            }
            if studentID.isEmpty { rowProblems.append("Student ID is blank.") }

            guard rowProblems.isEmpty else {
                let label = [lastName, firstName].filter { !$0.isEmpty }.joined(separator: ", ")
                let prefix = label.isEmpty
                    ? (studentID.isEmpty ? "" : "Student ID \(studentID) — ")
                    : "\(label) — "
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: prefix + problem))
                }
                continue
            }

            result.rows.append([
                "Student ID": studentID,
                "Student First Name": firstName,
                "Student Last Name": lastName,
                "School Year": schoolYear,
                "Tag Name": tagName,
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
