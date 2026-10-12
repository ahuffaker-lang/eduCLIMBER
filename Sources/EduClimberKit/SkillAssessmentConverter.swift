import Foundation

/// Skill Assessment Student List export (Letter Identification, Letter
/// Sounds, and similar single-administration skills assessments) ->
/// eduCLIMBER Generic Assessment.
///
/// The export itself has no grade or school -- those come from a second file,
/// an Aeries pull of Student ID / Grade / School, joined here by Student ID.
/// A student missing from that file, or coded with a grade this district
/// hasn't used before, is flagged for review rather than guessed at; an
/// unrecognized school code is a notice only, since School isn't one of
/// eduCLIMBER's columns here -- it would only matter for a per-school report
/// this converter doesn't build.
public struct SkillAssessmentConverter: AssessmentConverter {
    public init() {}

    public let key = "skill_assessment"
    public let displayName = "Skill Assessment (Letter ID, Letter Sounds, etc.)"
    public let summary =
        "Renaissance/Illuminate Skill Assessment Student List export -- one block per teacher, "
        + "not one row per student -- joined against an Aeries grade/school file by Student ID. "
        + "Covers any single-administration skills assessment: Letter Identification, Letter "
        + "Sounds, and similar."

    public var prompts: [PromptField] {
        [
            PromptField(
                key: "assessment_group", label: "Assessment Group", kind: .text(pattern: ".*"),
                help: "Must match an existing eduCLIMBER assessment group exactly.",
                placeholder: "Foundational Skills"),
            PromptField(
                key: "assessment_window", label: "Assessment Window", kind: .text(pattern: ".*"),
                help: "e.g. Test 1, Admin 1, Fall, or Yearly if the assessment has no window.",
                placeholder: "Test 1"),
            PromptField(
                key: "school_year", label: "School Year",
                kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
                help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
                placeholder: "2026-2027", defaultValue: EurekaMathConverter.currentSchoolYear()),
            PromptField(
                key: "aeries_file", label: "Aeries Grade/School File", kind: .file,
                help: "A 3-column export: Student ID, Grade, and School (Aeries codes)."),
        ]
    }

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "student_name", label: "Student Name", example: "Flores, Alexander"),
        SourceColumn(key: "student_id", label: "Student ID", example: "20221371"),
        SourceColumn(key: "total_attempts", label: "Total Attempts", example: "1"),
        SourceColumn(key: "number_correct", label: "Number Correct", example: "26"),
        SourceColumn(key: "number_answered", label: "Number Answered", example: "26"),
        SourceColumn(key: "percent_earned", label: "Percent Earned", example: "100.0%"),
        SourceColumn(
            key: "correct_questions", label: "Correct Questions", isRequired: false,
            example: "a, b, c"),
        SourceColumn(key: "assessment_name", label: "Assessment Name", example: "26-27 Letter Sounds"),
    ]

    /// The Aeries file's own three columns -- matched by name, since the
    /// spec notes their order in that export isn't guaranteed.
    static let aeriesColumns: [SourceColumn] = [
        SourceColumn(key: "student_id", label: "Student ID", aliases: ["StudentID", "ID"],
                     example: "20221371"),
        SourceColumn(key: "grade", label: "Grade", example: "0"),
        SourceColumn(key: "school", label: "School", example: "667"),
    ]

    public let outputColumns = [
        "Assessment Group", "Assessment Name", "Assessment Window", "School Year",
        "Student ID", "Student First Name", "Student Middle Initial", "Student Last Name",
        "Date of Birth", "Student Grade Level", "Score",
        "Score Detail 1 Number Correct", "Score Detail 2 Total Attempts",
        "Score Detail 3 Correct Letters",
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
        let assessmentWindow = trimmed(answers["assessment_window"])
        let schoolYear = trimmed(answers["school_year"])
        let assessmentName = table.value(table.rows[0], header("assessment_name"))
        guard !assessmentName.isEmpty else {
            throw ConverterError(
                "Could not detect the assessment's name from the file -- "
                + "its Assessment row may be malformed.")
        }

        let aeriesPath = trimmed(answers["aeries_file"])
        guard !aeriesPath.isEmpty else {
            throw ConverterError("Choose the Aeries grade/school file before converting.")
        }
        let aeriesLookup = try Self.loadAeriesLookup(path: aeriesPath)

        var result = ConversionResult(columns: outputColumns)
        var seenStudentIDs = Set<String>()

        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let studentName = table.value(row, header("student_name"))
            let studentID = table.value(row, header("student_id"))
            let totalAttempts = table.value(row, header("total_attempts"))
            let numberCorrect = table.value(row, header("number_correct"))
            let numberAnswered = table.value(row, header("number_answered"))
            let percentText = table.value(row, header("percent_earned"))
            let correctQuestions = table.value(row, header("correct_questions"))

            var rowProblems: [String] = []
            var rowNotices: [String] = []
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

            var grade = ""
            if studentID.isEmpty {
                // Already flagged above; a blank ID can't be looked up.
            } else if let match = aeriesLookup[studentID] {
                if let mappedGrade = match.grade {
                    grade = mappedGrade
                    if grade == "TK" {
                        rowNotices.append(
                            "Student is coded TK -- confirm eduCLIMBER accepts this grade.")
                    }
                } else {
                    rowProblems.append(
                        "Grade code '\(match.rawGrade)' for Student ID \(studentID) is not "
                        + "recognized.")
                }
                if match.school == nil {
                    rowNotices.append(
                        "School code '\(match.rawSchool)' for Student ID \(studentID) is not "
                        + "recognized.")
                }
            } else {
                rowProblems.append(
                    "Student ID \(studentID) was not found in the Aeries grade/school file.")
            }

            if Int(totalAttempts) == nil {
                rowProblems.append("Total Attempts '\(totalAttempts)' is not a number.")
            }
            if Int(numberCorrect) == nil {
                rowProblems.append("Number Correct '\(numberCorrect)' is not a number.")
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

            if numberAnswered.trimmingCharacters(in: .whitespaces) == "0" {
                rowNotices.append("0 questions were answered -- this would upload as a score of 0.")
            } else if rowProblems.isEmpty && score == 0 {
                rowNotices.append("Score is 0 -- confirm the assessment was really given.")
            }

            let label = studentName.isEmpty
                ? (studentID.isEmpty ? "" : "Student ID \(studentID)")
                : studentName
            let labelPrefix = label.isEmpty ? "" : "\(label) — "

            for notice in rowNotices {
                result.notices.append(RowError(rowNumber: rowNumber, message: labelPrefix + notice))
            }

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
                "Score Detail 1 Number Correct": numberCorrect,
                "Score Detail 2 Total Attempts": totalAttempts,
                "Score Detail 3 Correct Letters": Self.cleanCorrectQuestions(correctQuestions),
            ]
            result.rows.append(output)
        }
        return result
    }

    // MARK: - The Aeries join

    struct AeriesMatch {
        let grade: String?
        let rawGrade: String
        let school: String?
        let rawSchool: String
    }

    static func loadAeriesLookup(path: String) throws -> [String: AeriesMatch] {
        let url = URL(fileURLWithPath: path)
        let aeriesTable: Table
        do {
            aeriesTable = try Pipeline.loadSource(at: url)
        } catch {
            throw ConverterError(
                "Could not read the Aeries grade/school file: \(error.localizedDescription)")
        }
        let mapping = resolveColumns(table: aeriesTable, columns: aeriesColumns)
        guard !mapping.needsConfirmation, mapping.problems().isEmpty else {
            throw ConverterError(
                "The Aeries grade/school file's columns could not be matched automatically.\n"
                + mapping.unmatchedMessage())
        }
        let idHeader = mapping.match(for: "student_id")?.header
        let gradeHeader = mapping.match(for: "grade")?.header
        let schoolHeader = mapping.match(for: "school")?.header

        var lookup: [String: AeriesMatch] = [:]
        for row in aeriesTable.rows {
            let id = aeriesTable.value(row, idHeader)
            guard !id.isEmpty else { continue }
            let rawGrade = aeriesTable.value(row, gradeHeader)
            let rawSchool = aeriesTable.value(row, schoolHeader)
            let grade = Int(rawGrade).flatMap(SkillAssessmentReferenceData.eduClimberGrade(forAeriesCode:))
            let school = Int(rawSchool).flatMap { SkillAssessmentReferenceData.schoolNames[$0] }
            lookup[id] = AeriesMatch(grade: grade, rawGrade: rawGrade, school: school, rawSchool: rawSchool)
        }
        return lookup
    }

    /// Remove all spaces and NBSP, then re-join with ", " -- the real export's
    /// spacing is inconsistent ("a , b  , c"), not already clean.
    static func cleanCorrectQuestions(_ raw: String) -> String {
        let noSpaces = raw
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !noSpaces.isEmpty else { return "" }
        return noSpaces.split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
            .joined(separator: ", ")
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
