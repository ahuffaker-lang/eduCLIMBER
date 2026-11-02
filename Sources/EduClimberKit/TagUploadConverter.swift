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
/// ("Last, First"), not separate first/last columns. School Year, Tag Name,
/// and Tag Flag are not in the source file at all -- they describe the batch
/// as a whole, so they're typed in once and stamped onto every row. Tag Flag
/// is the one eduCLIMBER tag-upload column not every district format
/// actually uses, so it's the one prompt here that can be left blank.
public struct TagUploadConverter: AssessmentConverter {
    public init() {}

    public let key = "tag_upload"
    public let displayName = "Tag Upload"
    public let summary =
        "Builds an eduCLIMBER tag upload (Student ID, Student First Name, Student Last Name, "
        + "School Year, Tag Name, Tag Flag) from any file that has a Student ID and a name -- "
        + "either a combined 'Student Name' column ('Last, First') or separate first/last name "
        + "columns -- whatever else it contains, and whatever those columns are called. School "
        + "Year and Tag Name are typed in once for the whole batch; Tag Flag is also typed in "
        + "and can be left blank for a tag format that doesn't use one."

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
        let tagFlag = trimmed(answers["tag_flag"])

        var result = ConversionResult(columns: outputColumns)
        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let studentID = table.value(row, header("student_id"))
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
                if splitFirst.isEmpty { rowProblems.append("Student First Name is blank.") }
                if splitLast.isEmpty { rowProblems.append("Student Last Name is blank.") }
            } else if !student.isEmpty {
                // One combined column: "Last, First".
                let name = RunningRecordsConverter.splitStudentName(student)
                firstName = name.first
                lastName = name.last
                if !student.contains(",") {
                    rowProblems.append("Student Name '\(student)' is not in 'Last, First' format.")
                } else if name.first.isEmpty || name.last.isEmpty {
                    rowProblems.append("Student Name '\(student)' is missing a first or last name.")
                }
            } else {
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
