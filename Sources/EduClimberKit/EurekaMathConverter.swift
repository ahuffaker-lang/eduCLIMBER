import Foundation

/// Eureka Math module assessments → eduCLIMBER.
///
/// The export mixes several kinds of assessment in one file -- Module
/// Assessments, Topic Quizzes, and (for grades 3-5) interim assessments --
/// identified by `type_of_assessment`. Only Module Assessments ("MA") are
/// what eduCLIMBER wants here; everything else is skipped without comment,
/// not flagged as a problem, since it was never meant to convert. Among
/// Module Assessment rows, `assessment_status` further distinguishes a
/// finished attempt ("done") from one still in progress -- that one *is*
/// flagged for review rather than skipped, since it is a real row someone
/// needs to look at, not noise.
public struct EurekaMathConverter: AssessmentConverter {
    public static let assessmentGroup = "Eureka Math"
    public static let assessmentName = "Eureka Math Module"
    /// The only `type_of_assessment` value that converts.
    public static let moduleAssessmentTypeCode = "MA"
    /// The only `assessment_status` value that converts without review.
    public static let doneStatus = "done"
    /// eduCLIMBER's "Eureka Math Grades 3-5" assessment doesn't cover K-2.
    public static let supportedGrades = ["3", "4", "5"]

    public init() {}

    public let key = "eureka_math"
    public let displayName = "Eureka Math"
    public let summary =
        "Eureka Math module assessment export (Type of Assessment, Assessment Status, Grade, "
        + "Module, Student Id, Student, Date Completed, Overall Percentage, Performance Band). "
        + "Only rows marked as a Module Assessment (MA) are converted; quizzes and other "
        + "assessment types are skipped. A Module Assessment not yet marked \"done\" is flagged "
        + "for review rather than converted."

    /// A single batch-wide value: the school year every row is stamped with.
    /// Pre-filled with the current academic year (computed from today's
    /// date) so the common case needs no typing, but a district re-running
    /// an older export can still override it.
    public var prompts: [PromptField] {
        [PromptField(
            key: "school_year",
            label: "School Year",
            kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
            help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
            placeholder: "2026-2027",
            defaultValue: Self.currentSchoolYear())]
    }

    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "type_of_assessment", label: "Type of Assessment", example: "MA"),
        SourceColumn(key: "assessment_status", label: "Assessment Status", example: "done"),
        SourceColumn(key: "grade", label: "Grade", example: "5"),
        SourceColumn(key: "module", label: "Module", example: "1"),
        SourceColumn(key: "student_id", label: "Student Id", aliases: ["Student ID"],
                     example: "20212318"),
        SourceColumn(key: "student", label: "Student", aliases: ["Student Name"],
                     example: "Garcia, Ethan"),
        SourceColumn(key: "date_completed", label: "Date Completed", example: "9/25/26"),
        SourceColumn(key: "overall_percentage", label: "Overall Percentage",
                     aliases: ["Overall %"], example: "86"),
        SourceColumn(key: "performance_band", label: "Performance Band", example: "proficient"),
    ]

    /// The 13 eduCLIMBER columns, in the order this template expects --
    /// Assessment Name before Assessment Group, and Last Name before First
    /// Name, both the reverse of Running Records' and HFW's order.
    public let outputColumns = [
        "Assessment Name",
        "Assessment Group",
        "Assessment Window",
        "School Year",
        "Student ID",
        "Student Last Name",
        "Student First Name",
        "Student Middle Initial",
        "Student Grade Level",
        "Date of Birth",
        "Score",
        "Score Detail 1 Proficiency Level",
        "Score Detail 2 Date Completed",
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

        var result = ConversionResult(columns: outputColumns)
        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let typeOfAssessment = table.value(row, header("type_of_assessment"))

            // Topic Quizzes and interim assessments are not what this batch is
            // for -- skip them silently rather than reporting them as problems.
            guard typeOfAssessment.caseInsensitiveCompare(Self.moduleAssessmentTypeCode)
                == .orderedSame
            else { continue }

            let assessmentStatus = table.value(row, header("assessment_status"))
            let studentID = table.value(row, header("student_id"))
            let student = table.value(row, header("student"))
            let rawGrade = table.value(row, header("grade"))
            let module = table.value(row, header("module"))
            let dateCompleted = table.value(row, header("date_completed"))
            let percentage = table.value(row, header("overall_percentage"))
            let performanceBand = table.value(row, header("performance_band"))

            var rowProblems: [String] = []
            var name = (first: "", last: "")

            // Unlike the type_of_assessment filter above, a Module Assessment
            // that is not yet "done" is a legitimate row someone needs to look
            // at -- it is flagged for review rather than skipped without
            // comment, since "open" here does not simply mean "not started".
            if assessmentStatus.caseInsensitiveCompare(Self.doneStatus) != .orderedSame {
                rowProblems.append(
                    assessmentStatus.isEmpty
                        ? "Assessment Status is blank."
                        : "Assessment Status '\(assessmentStatus)' is not \"\(Self.doneStatus)\" "
                            + "-- flagged for review.")
            }

            if studentID.isEmpty { rowProblems.append("Student Id is blank.") }

            if student.isEmpty {
                rowProblems.append("Student is blank.")
            } else if !student.contains(",") {
                rowProblems.append("Student '\(student)' is not in 'Last, First' format.")
            } else {
                name = RunningRecordsConverter.splitStudentName(student)
                if name.first.isEmpty || name.last.isEmpty {
                    rowProblems.append("Student '\(student)' is missing a first or last name.")
                }
            }

            let grade = Self.normalizeGrade(rawGrade)
            if grade == nil {
                rowProblems.append(
                    rawGrade.isEmpty
                        ? "Grade is blank."
                        : "Grade '\(rawGrade)' is not recognized.")
            } else if let grade, !Self.supportedGrades.contains(grade) {
                rowProblems.append(
                    "Grade \(grade) is not covered by the Eureka Math Grades 3-5 assessment "
                    + "in eduCLIMBER.")
            }

            if module.isEmpty {
                rowProblems.append("Module is blank.")
            } else if !(1...6).contains(Int(module) ?? -1) {
                rowProblems.append(
                    "Module '\(module)' is not one of eduCLIMBER's Module 1-6 windows.")
            }
            if dateCompleted.isEmpty { rowProblems.append("Date Completed is blank.") }
            if percentage.isEmpty { rowProblems.append("Overall Percentage is blank.") }
            if performanceBand.isEmpty { rowProblems.append("Performance Band is blank.") }

            var label = student.isEmpty
                ? [name.last, name.first].filter { !$0.isEmpty }.joined(separator: ", ")
                : student
            if label.isEmpty && !studentID.isEmpty { label = "Student ID \(studentID)" }
            let labelPrefix = label.isEmpty ? "" : "\(label) — "

            guard rowProblems.isEmpty, let grade else {
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: labelPrefix + problem))
                }
                continue
            }

            let output: [String: String] = [
                "Assessment Name": Self.assessmentName,
                "Assessment Group": Self.assessmentGroup,
                "Assessment Window": "Module \(module)",
                "School Year": schoolYear,
                "Student ID": studentID,
                "Student Last Name": name.last,
                "Student First Name": name.first,
                "Student Middle Initial": "",
                "Student Grade Level": grade,
                "Date of Birth": "",
                "Score": percentage,
                "Score Detail 1 Proficiency Level": performanceBand,
                "Score Detail 2 Date Completed": dateCompleted,
            ]
            result.rows.append(output)
        }
        return result
    }

    /// "5" stays "5"; also tolerates "Grade 5" / "5th Grade" / "Kindergarten"
    /// in case a differently-shaped export ever reuses this converter.
    static func normalizeGrade(_ raw: String) -> String? {
        HFWConverter.normalizeGrade(raw)
    }

    /// The academic year containing `referenceDate`, assuming a July cutoff
    /// (a completion date from July onward belongs to the year that starts
    /// that July; earlier in the calendar year, to the one that started the
    /// previous July).
    static func currentSchoolYear(referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let year = components.year, let month = components.month else { return "" }
        return month >= 7 ? "\(year)-\(year + 1)" : "\(year - 1)-\(year)"
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
