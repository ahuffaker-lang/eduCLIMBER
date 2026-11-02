import Foundation

/// Any student list → eduCLIMBER tag upload.
///
/// Unlike every other converter here, the source file isn't one fixed export:
/// it's whatever list of students the user happens to be tagging this time,
/// built fresh for the purpose and never shaped the same way twice. The only
/// promise is that it has a Student ID, a first name, and a last name
/// somewhere in it -- under whatever headers that particular file uses -- so
/// those three are matched the same loose, alias-and-similarity way every
/// other converter's columns are, rather than assumed to have fixed names.
/// School Year, Tag Name, and Tag Flag are not in the source file at all --
/// they describe the batch as a whole, so they're typed in once and stamped
/// onto every row. Tag Flag is the one eduCLIMBER tag-upload column not every
/// district format actually uses, so it's the one prompt here that can be
/// left blank.
public struct TagUploadConverter: AssessmentConverter {
    public init() {}

    public let key = "tag_upload"
    public let displayName = "Tag Upload"
    public let summary =
        "Builds an eduCLIMBER tag upload (Student ID, Student First Name, Student Last Name, "
        + "School Year, Tag Name, Tag Flag) from any file that has a Student ID, first name, "
        + "and last name column -- whatever else it contains, and whatever those columns are "
        + "called. School Year and Tag Name are typed in once for the whole batch; Tag Flag is "
        + "also typed in and can be left blank for a tag format that doesn't use one."

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
                key: "tag_flag", label: "Tag Flag", kind: .text(pattern: ".*"),
                help: "Leave blank if this tag upload format doesn't use a flag value.",
                placeholder: "Y", isRequired: false),
        ]
    }

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(
            key: "student_id", label: "Student ID",
            aliases: ["ID", "StudentID", "Student Identifier", "Student Number"],
            example: "20212318"),
        SourceColumn(
            key: "first_name", label: "Student First Name",
            aliases: ["First Name", "FirstName", "Given Name"],
            example: "Ethan"),
        SourceColumn(
            key: "last_name", label: "Student Last Name",
            aliases: ["Last Name", "LastName", "Surname", "Family Name"],
            example: "Garcia"),
    ]

    public let outputColumns = [
        "Student ID", "Student First Name", "Student Last Name",
        "School Year", "Tag Name", "Tag Flag",
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

        let schoolYear = trimmed(answers["school_year"])
        let tagName = trimmed(answers["tag_name"])
        let tagFlag = trimmed(answers["tag_flag"])

        var result = ConversionResult(columns: outputColumns)
        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let studentID = table.value(row, header("student_id"))
            let firstName = table.value(row, header("first_name"))
            let lastName = table.value(row, header("last_name"))

            var rowProblems: [String] = []
            if studentID.isEmpty { rowProblems.append("Student ID is blank.") }
            if firstName.isEmpty { rowProblems.append("Student First Name is blank.") }
            if lastName.isEmpty { rowProblems.append("Student Last Name is blank.") }

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

    /// Tag name rather than window -- this converter has no assessment
    /// window -- so two tags run the same day still land on different files.
    public var defaultFileNameTemplate: String { "{tag_name}_{year}_tag_upload" }

    public func defaultOutputName(answers: [String: String]) -> String {
        let tokens = FileNameTemplate.tokens(converter: self, answers: answers)
        return FileNameTemplate(defaultFileNameTemplate).render(tokens: tokens)
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
