import Foundation

/// Running Records → eduCLIMBER.
///
/// Source export columns: Student ("Last, First"), Student ID, Grade Level,
/// Reading Level (A-Z), Proficiency Level.
public struct RunningRecordsConverter: AssessmentConverter {
    public static let assessmentGroup = "Running Records"
    public static let assessmentName = "Independent Reading Level"
    /// Spanish records are a separate assessment in eduCLIMBER, under the same
    /// group, so the name carries the language while the group does not.
    public static let spanishAssessmentName = "Independent Reading Level Spanish"

    public static func assessmentName(forLanguage language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.caseInsensitiveCompare("Spanish") == .orderedSame
            ? spanishAssessmentName
            : assessmentName
    }
    public static let assessmentWindows = ["Trimester 1", "Trimester 2", "Trimester 3"]
    public static let languages = ["English", "Spanish"]
    public static let schoolYearPattern = "^[0-9]{4}-[0-9]{4}$"

    public init() {}

    public let key = "running_records"
    public let displayName = "Running Records"
    public let summary =
        "Reading assessment export (Student, Student ID, Grade Level, "
        + "Reading Level (A-Z), Proficiency Level)."

    public let prompts: [PromptField] = [
        PromptField(
            key: "assessment_window",
            label: "Assessment Window",
            kind: .choice(RunningRecordsConverter.assessmentWindows)),
        PromptField(
            key: "language",
            label: "Language",
            kind: .choice(RunningRecordsConverter.languages)),
        PromptField(
            key: "school_year",
            label: "School Year",
            kind: .text(pattern: RunningRecordsConverter.schoolYearPattern),
            help: "School Year must look like YYYY-YYYY with no spaces (e.g. 2026-2027).",
            placeholder: "2026-2027"),
    ]

    // The name can arrive either way, so all three name columns are optional on
    // their own: a file needs the combined column OR the split pair, which
    // `problems(for:)` below enforces.
    public let sourceColumns: [SourceColumn] = [
        SourceColumn(key: "student", label: "Student", aliases: ["Student Name"],
                     isRequired: false, example: "Gomez, Maria"),
        SourceColumn(key: "first_name", label: "First Name",
                     aliases: ["Given Name", "Student First Name"],
                     isRequired: false, example: "Maria"),
        SourceColumn(key: "last_name", label: "Last Name",
                     aliases: ["Surname", "Family Name", "Student Last Name"],
                     isRequired: false, example: "Gomez"),
        SourceColumn(key: "student_id", label: "Student ID",
                     aliases: ["Student Identifier", "Student Number"], example: "100234"),
        SourceColumn(key: "grade", label: "Grade Level", aliases: ["Grade"],
                     example: "K, 1, 2 ... 8"),
        SourceColumn(key: "reading_level", label: "Reading Level (A-Z)",
                     aliases: ["Reading Level", "Independent Reading Level"],
                     example: "Below A, A ... Z"),
        SourceColumn(key: "proficiency", label: "Proficiency Level", aliases: ["Proficiency"],
                     example: "At Standard"),
    ]

    /// The 13 eduCLIMBER columns, in the order the import expects. "Score
    /// Detail 2 Reading Level" and "Score Detail 1 Proficiency Level" are each
    /// one column with a combined header, not two columns repeating the same
    /// value -- that's what eduCLIMBER's own template calls them.
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
        "Score Detail 2 Reading Level",
        "Score Detail 1 Proficiency Level",
        "Score",
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
        "This file needs the student name: either a 'Student' column in "
        + "'Last, First' form, or separate 'First Name' and 'Last Name' columns."

    public func convert(
        table: Table, answers: [String: String], columns: [String: String?]
    ) throws -> ConversionResult {
        let window = trimmed(answers["assessment_window"])
        let schoolYear = trimmed(answers["school_year"])
        let language = trimmed(answers["language"])
        let assessmentName = Self.assessmentName(forLanguage: language)

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

        // Both are whole-batch, not per-row: every row shares one language and one
        // assessment window, so a problem with either is reported once up front
        // rather than repeated on every row.
        guard let benchmark = BenchmarkRegistry.select(language: language, schoolYear: schoolYear) else {
            throw ConverterError(
                "No benchmark table is registered for '\(language)'. This is a setup "
                + "problem, not something wrong with the file -- add a rubric for this "
                + "language to BenchmarkRegistry.")
        }
        guard let trimesterKey = Self.trimesterKey(forWindow: window) else {
            throw ConverterError("Unrecognized Assessment Window '\(window)'.")
        }

        var result = ConversionResult(columns: outputColumns)
        for (index, row) in table.rows.enumerated() {
            let rowNumber = table.rowNumber(index)
            let student = table.value(row, header("student"))
            let studentID = table.value(row, header("student_id"))
            let grade = table.value(row, header("grade"))
            let readingLevel = table.value(row, header("reading_level"))
            let proficiency = table.value(row, header("proficiency"))

            var rowProblems: [String] = []
            var name = (first: "", last: "")

            let splitFirst = table.value(row, firstHeader)
            let splitLast = table.value(row, lastHeader)
            if useSplitNames && !(splitFirst.isEmpty && splitLast.isEmpty) {
                // Already split by the source system: use the values as they are.
                name = (first: splitFirst, last: splitLast)
                if splitFirst.isEmpty { rowProblems.append("First Name is blank.") }
                if splitLast.isEmpty { rowProblems.append("Last Name is blank.") }
            } else if !student.isEmpty {
                // One combined column: "Last, First".
                name = Self.splitStudentName(student)
                if !student.contains(",") {
                    rowProblems.append("Student name '\(student)' is not in 'Last, First' format.")
                } else if name.first.isEmpty || name.last.isEmpty {
                    rowProblems.append("Student name '\(student)' is missing a first or last name.")
                }
            } else {
                rowProblems.append("Student name is blank.")
            }
            if studentID.isEmpty {
                rowProblems.append("Student ID is blank.")
            }

            let score = ReadingLevels.score(for: readingLevel)
            if score == nil {
                if readingLevel.isEmpty {
                    rowProblems.append("Reading Level (A-Z) is blank.")
                } else {
                    rowProblems.append(
                        "Reading Level '\(readingLevel)' is not in the reading level table.")
                }
            }

            // The benchmark only covers Kindergarten through Grade 5, and
            // Kindergarten has no scale in Trimester 1. A row outside that
            // coverage is never excluded -- real data turns up grades the rubric
            // doesn't plan for (a 6th grader in a Spanish Running Records file,
            // for instance), and dropping the row would just push the manual work
            // this app exists to remove back onto the user. Instead the row
            // exports with whatever Proficiency Level the sheet already had
            // (blank if it had none), and a notice below says why it wasn't
            // scored. A disagreement with the sheet's own Proficiency Level for a
            // row the benchmark *does* cover also does not exclude the row --
            // that becomes a notice too, so it can be spot-checked rather than
            // pass silently.
            var benchmarkScore: Int?
            var benchmarkGradeKey: String?
            var benchmarkSkippedReason: String?
            if let gradeKey = BenchmarkGrade.key(forSourceGrade: grade) {
                benchmarkGradeKey = gradeKey
                if let cell = benchmark.rubric.cell(grade: gradeKey, trimester: trimesterKey),
                   cell.hasScale {
                    if let computed = cell.score(forLevel: readingLevel) {
                        benchmarkScore = computed
                    } else if score != nil {
                        // Should not happen once a rubric tiles Below A...Z+ cleanly
                        // (every shipped table is tested for that), but never silently
                        // guess at a score.
                        rowProblems.append(
                            "The \(benchmark.rubric.label) benchmark has no band for reading "
                            + "level '\(readingLevel)' at \(Self.displayGrade(gradeKey)) \(window).")
                    }
                } else {
                    benchmarkSkippedReason =
                        "\(Self.displayGrade(gradeKey)) \(window) has no benchmark scale in "
                        + "the \(benchmark.rubric.label) table; the row was exported without a "
                        + "computed Proficiency Level."
                }
            } else {
                benchmarkSkippedReason = Self.benchmarkGradeSkippedMessage(
                    rawGrade: grade, rubricLabel: benchmark.rubric.label)
            }

            var label = student
            if label.isEmpty && !(name.first.isEmpty && name.last.isEmpty) {
                label = [name.last, name.first].filter { !$0.isEmpty }.joined(separator: ", ")
            }
            if label.isEmpty && !studentID.isEmpty { label = "Student ID \(studentID)" }
            let labelPrefix = label.isEmpty ? "" : "\(label) — "

            guard rowProblems.isEmpty, let score else {
                for problem in rowProblems {
                    result.errors.append(RowError(rowNumber: rowNumber, message: labelPrefix + problem))
                }
                continue
            }

            // The benchmark's score wins when it disagrees with what the sheet
            // already carried, but the disagreement is surfaced as a notice rather
            // than applied silently. A blank source value is filled in without
            // comment -- that is the ordinary case, not something to flag.
            var finalProficiency = proficiency
            if let benchmarkScore {
                let computedText = String(benchmarkScore)
                if proficiency.isEmpty || proficiency == computedText {
                    finalProficiency = computedText
                } else {
                    finalProficiency = computedText
                    result.notices.append(RowError(
                        rowNumber: rowNumber,
                        message: labelPrefix + "sheet Proficiency Level was '\(proficiency)'; "
                            + "the \(benchmark.rubric.label) benchmark for "
                            + "\(Self.displayGrade(benchmarkGradeKey ?? grade)) \(window) at "
                            + "level \(readingLevel) is \(computedText). The benchmark value was used."))
                }
            } else if let benchmarkSkippedReason {
                result.notices.append(
                    RowError(rowNumber: rowNumber, message: labelPrefix + benchmarkSkippedReason))
            }

            // Annotated so the type-checker does not have to solve a 15-entry
            // literal from context.
            let output: [String: String] = [
                "Assessment Group": Self.assessmentGroup,
                "Assessment Name": assessmentName,
                "Assessment Window": window,
                "School Year": schoolYear,
                "Student ID": studentID,
                "Student First Name": name.first,
                "Student Middle Initial": "",
                "Student Last Name": name.last,
                "Date of Birth": "",
                "Student Grade Level": grade,
                "Score Detail 2 Reading Level": readingLevel,
                "Score Detail 1 Proficiency Level": finalProficiency,
                "Score": String(score),
            ]
            result.rows.append(output)
        }
        return result
    }

    static func trimesterKey(forWindow window: String) -> String? {
        switch window {
        case "Trimester 1": return "T1"
        case "Trimester 2": return "T2"
        case "Trimester 3": return "T3"
        default: return nil
        }
    }

    static func displayGrade(_ key: String) -> String {
        key == "Kinder" ? "Kindergarten" : key
    }

    static func benchmarkGradeSkippedMessage(rawGrade: String, rubricLabel: String) -> String {
        let trimmedGrade = rawGrade.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGrade.isEmpty {
            return "Grade Level is blank, so a \(rubricLabel) benchmark score could not be "
                + "determined; the row was exported without a computed Proficiency Level."
        }
        return "Grade Level '\(trimmedGrade)' is not covered by the \(rubricLabel) benchmark "
            + "(Kindergarten through Grade 5); the row was exported without a computed "
            + "Proficiency Level."
    }

    public func scoringTableSummary(for answers: [String: String]) -> ScoringTableSummary? {
        let language = trimmed(answers["language"])
        let schoolYear = trimmed(answers["school_year"])
        guard !language.isEmpty, !schoolYear.isEmpty,
              let selection = BenchmarkRegistry.select(language: language, schoolYear: schoolYear)
        else { return nil }

        let text = "Benchmark: \(selection.rubric.label) · Grades K-5 scored, other grades pass through"
        guard selection.isCarriedForward, let requested = selection.requestedStartYear else {
            return ScoringTableSummary(text: text)
        }
        return ScoringTableSummary(
            text: text,
            isCarriedForward: true,
            carriedForwardNote: "no table for \(requested)-\(requested + 1) yet")
    }

    /// English and Spanish batches share a window and a school year, so the
    /// language has to be in the name for the two files to sit side by side.
    public var defaultFileNameTemplate: String {
        "Running_Records_{language}_{window}_{year}_educlimber"
    }

    public func defaultOutputName(answers: [String: String]) -> String {
        let tokens = FileNameTemplate.tokens(converter: self, answers: answers)
        return FileNameTemplate(defaultFileNameTemplate).render(tokens: tokens)
    }

    /// Split "Last, First" into its parts. An extra comma ("Last, First, Jr")
    /// keeps everything after the first comma as the first-name text.
    public static func splitStudentName(_ raw: String) -> (first: String, last: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = text.firstIndex(of: ",") else { return ("", "") }
        let last = String(text[text.startIndex..<comma])
        let first = String(text[text.index(after: comma)...])
        return (
            first.trimmingCharacters(in: .whitespacesAndNewlines),
            last.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
