import Foundation

/// High Frequency Words, exported via Illuminate's "Skill Assessment Student
/// List" template (the same block-per-teacher layout Letter ID and Letter
/// Sounds use) -> eduCLIMBER Generic Assessment.
///
/// Unlike that export, there is no Performance Band column here: Illuminate
/// has already scored each student, so Percent Earned is taken as the Score
/// directly -- eduCLIMBER's own configured benchmark/performance ranges do
/// the leveling once it's uploaded -- and the list of words a student
/// answered correctly becomes a Score Detail column instead of a letter
/// list. Each file covers one grade and one administration (e.g. "26-27
/// Kinder HFW List 1 & 2"), so Grade, Assessment Group/Name, Assessment
/// Window, and School Year are all batch-wide prompts rather than parsed
/// from the file -- there's no naming pattern reliable enough to parse
/// across grades and future word lists, and the Assessment Name has to
/// match eduCLIMBER's own configured name exactly anyway.
public struct HFWListConverter: AssessmentConverter {
    public init() {}

    public let key = "hfw_skill_list"
    public let displayName = "High Frequency Words (Skill List Export)"
    public let summary =
        "High Frequency Words via the Illuminate Skill Assessment Student List export -- one "
        + "block per teacher, not one row per student. There's no Performance Band here: "
        + "Percent Earned is taken as the Score directly, and the list of words each student "
        + "answered correctly becomes a Score Detail column. One grade and one administration "
        + "per file, so Grade, Assessment Group/Name, Window, and School Year are all typed in."

    public var prompts: [PromptField] {
        [
            PromptField(
                key: "assessment_group", label: "Assessment Group", kind: .text(pattern: ".*"),
                help: "Must match an existing eduCLIMBER assessment group exactly.",
                placeholder: "High Frequency Words"),
            PromptField(
                key: "assessment_name", label: "Assessment Name", kind: .text(pattern: ".*"),
                help: "Must match an existing eduCLIMBER assessment name exactly.",
                placeholder: "26-27 Kindergarten High Frequency Words List 1-2"),
            PromptField(
                key: "assessment_window", label: "Assessment Window",
                kind: .choice(["Test 1", "Test 2", "Test 3"])),
            PromptField(
                key: "grade", label: "Grade", kind: .text(pattern: ".*"),
                help: "Every student in this file shares one grade -- e.g. K, 1, 2.",
                placeholder: "K"),
            PromptField(
                key: "school_year", label: "School Year",
                kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
                help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
                placeholder: "2026-2027", defaultValue: EurekaMathConverter.currentSchoolYear()),
        ]
    }

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "student_name", label: "Student Name", example: "Azucena, Rene"),
        SourceColumn(key: "student_id", label: "Student ID", example: "20220530"),
        SourceColumn(key: "percent_earned", label: "Percent Earned", example: "94.0%"),
        SourceColumn(
            key: "correct_questions", label: "Correct Questions", isRequired: false,
            example: "a, an, at, for, I, in, is, it, like, me, the, you"),
    ]

    public let outputColumns = [
        "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
        "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
        "Date of Birth", "Student Grade Level", "Score", "Score Detail 1 Words Correct",
    ]

    public func loadSource(at url: URL) throws -> Table {
        try SkillAssessmentReader.read(contentsOf: url)
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

        let assessmentGroup = trimmed(answers["assessment_group"])
        let assessmentName = trimmed(answers["assessment_name"])
        let assessmentWindow = trimmed(answers["assessment_window"])
        let grade = trimmed(answers["grade"])
        let schoolYear = trimmed(answers["school_year"])

        var result = ConversionResult(columns: outputColumns)
        var seenStudentIDs = Set<String>()

        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let studentName = table.value(row, header("student_name"))
            let studentID = table.value(row, header("student_id"))
            let percentText = table.value(row, header("percent_earned"))
            let correctQuestions = table.value(row, header("correct_questions"))

            var rowProblems: [String] = []
            var name = (first: "", last: "")

            if studentID.isEmpty {
                rowProblems.append("Student ID is blank.")
            } else if !seenStudentIDs.insert(studentID).inserted {
                rowProblems.append("Student ID \(studentID) appears more than once in this file.")
            }

            if studentName.isEmpty {
                rowProblems.append("Student Name is blank.")
            } else if !studentName.contains(",") {
                rowProblems.append("Student Name '\(studentName)' is not in 'Last, First' format.")
            } else {
                let parsed = RunningRecordsConverter.splitStudentName(studentName)
                name.last = parsed.last
                name.first = SkillAssessmentReferenceData.nameFixes[studentID] ?? parsed.first
                if name.last.isEmpty {
                    rowProblems.append("Student Name '\(studentName)' is missing a last name.")
                }
                if name.first.isEmpty {
                    rowProblems.append(
                        "Student Name '\(studentName)' is missing a first name, and "
                        + "\(studentID.isEmpty ? "this student" : studentID) isn't in the "
                        + "Name Fixes table yet.")
                }
            }

            var score = 0
            let percentValue = Double(
                percentText.trimmingCharacters(in: CharacterSet(charactersIn: "%"))
                    .trimmingCharacters(in: .whitespaces))
            if let percentValue {
                score = Int(percentValue.rounded())
            } else {
                rowProblems.append("Percent Earned '\(percentText)' is not a number.")
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

            let output: [String: String] = [
                "Assessment Group": assessmentGroup,
                "Assessment Name": assessmentName,
                "Assessment Window": assessmentWindow,
                "School Year": schoolYear,
                "Student ID": studentID,
                "Student First Name": name.first,
                "Student Middle Initial": "",
                "Student Last Name": name.last,
                "Date of Birth": "",
                "Student Grade Level": grade,
                "Score": String(score),
                "Score Detail 1 Words Correct":
                    SkillAssessmentConverter.cleanCorrectQuestions(correctQuestions),
            ]
            result.rows.append(output)
        }
        return result
    }

    public func defaultOutputName(answers: [String: String]) -> String {
        let tokens = FileNameTemplate.tokens(converter: self, answers: answers)
        return FileNameTemplate(defaultFileNameTemplate).render(tokens: tokens)
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
