import Foundation

/// One value the user supplies for a whole batch.
public struct PromptField {
    public enum Kind {
        case choice([String])
        case text(pattern: String)
        /// A path to a second file this batch needs (e.g. a roster to join
        /// against). The control that renders it is responsible for putting a
        /// real, chosen path into the answer; beyond "something was chosen",
        /// whether that file is actually readable and shaped right is for the
        /// converter to report when it tries to read it.
        case file
    }

    public let key: String
    public let label: String
    public let kind: Kind
    public let help: String
    public let placeholder: String
    /// Pre-filled into the control when the prompt is first shown -- e.g. the
    /// current school year, computed from today's date, so the common case
    /// needs no typing but can still be overridden.
    public let defaultValue: String?
    /// False for a batch setting that is genuinely optional -- e.g. a flag
    /// column some tag upload formats don't use at all. Leaving it blank is
    /// then not a problem; everything else still has to be filled in.
    public let isRequired: Bool

    public init(
        key: String, label: String, kind: Kind, help: String = "", placeholder: String = "",
        defaultValue: String? = nil, isRequired: Bool = true
    ) {
        self.key = key
        self.label = label
        self.kind = kind
        self.help = help
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.isRequired = isRequired
    }

    public var choices: [String] {
        if case .choice(let options) = kind { return options }
        return []
    }

    /// An error message, or nil when the value is acceptable.
    public func validate(_ value: String?) -> String? {
        let value = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return isRequired ? "\(label) is required." : nil }
        switch kind {
        case .choice(let options):
            guard options.contains(value) else {
                return "\(label) must be one of: \(options.joined(separator: ", "))."
            }
        case .text(let pattern):
            guard value.range(of: pattern, options: .regularExpression) != nil else {
                return help.isEmpty ? "\(label) is not in the expected format." : help
            }
        case .file:
            break  // non-empty (a path was chosen) is all that's checked here
        }
        return nil
    }
}

/// A column a converter needs to find in the uploaded file.
public struct SourceColumn: Equatable {
    public let key: String
    /// The canonical name, shown to the user when asking about a column.
    public let label: String
    public let aliases: [String]
    public let isRequired: Bool
    public let example: String

    public init(
        key: String, label: String, aliases: [String] = [],
        isRequired: Bool = true, example: String = ""
    ) {
        self.key = key
        self.label = label
        self.aliases = aliases
        self.isRequired = isRequired
        self.example = example
    }

    public var matchNames: [String] { [label] + aliases }
}

/// A problem found in one row of the source file.
public struct RowError: Equatable {
    /// 1-based spreadsheet row number, as shown in Excel.
    public let rowNumber: Int
    public let message: String

    public init(rowNumber: Int, message: String) {
        self.rowNumber = rowNumber
        self.message = message
    }

    public var description: String { "Row \(rowNumber): \(message)" }
}

/// A separate, focused report meant to be acted on apart from the general
/// issues list -- handed to a teacher, followed up on next week -- rather
/// than just another line in the same problems report. For example, the
/// students a Formative export shows as assigned but never submitted: that's
/// still a blocking problem for the row (there's no score to upload), but
/// the follow-up isn't "fix this file," it's "go chase down these students."
public struct FollowUpReport: Equatable {
    public let title: String
    public let columns: [String]
    public let rows: [[String: String]]

    public init(title: String, columns: [String], rows: [[String: String]]) {
        self.title = title
        self.columns = columns
        self.rows = rows
    }
}

/// A row that converted cleanly -- every required field is present and
/// valid -- but still needs a human decision before it can be exported, e.g.
/// an assessment not yet marked complete. Shown in the review window with a
/// checkbox rather than as a Problem (nothing is wrong with it) or silently
/// included (the converter can't decide this on its own).
public struct ReviewRow: Equatable {
    /// 1-based spreadsheet row number, as shown in Excel.
    public let rowNumber: Int
    /// A short label identifying the row, e.g. "Garcia, Ethan".
    public let label: String
    /// The value that triggered review, e.g. the raw Assessment Status.
    public let status: String
    /// The fully-built output row -- ready to export as-is if approved.
    public let output: [String: String]

    public init(rowNumber: Int, label: String, status: String, output: [String: String]) {
        self.rowNumber = rowNumber
        self.label = label
        self.status = status
        self.output = output
    }
}

public struct ConversionResult {
    public var columns: [String]
    public var rows: [[String: String]]
    public var errors: [RowError]
    /// Informational, non-blocking findings -- currently just a benchmark score
    /// that disagreed with the value already in the source file. The row still
    /// converts (with the benchmark's value); a notice just surfaces the
    /// disagreement rather than let it pass silently.
    public var notices: [RowError]
    /// Rows awaiting an approve/deny decision -- see `ReviewRow`. Resolved by
    /// `resolvingReviewRows(approved:)` once the user has decided.
    public var reviewRows: [ReviewRow]
    /// A converter-specific report worth saving as its own file alongside the
    /// main export. `nil` when a converter has nothing like this (the default).
    public var followUpReport: FollowUpReport?

    public init(
        columns: [String], rows: [[String: String]] = [],
        errors: [RowError] = [], notices: [RowError] = [], reviewRows: [ReviewRow] = [],
        followUpReport: FollowUpReport? = nil
    ) {
        self.columns = columns
        self.rows = rows
        self.errors = errors
        self.notices = notices
        self.reviewRows = reviewRows
        self.followUpReport = followUpReport
    }

    public var isClean: Bool { errors.isEmpty }

    /// Rows that converted and can be exported.
    public var hasUsableRows: Bool { !rows.isEmpty }

    /// Applies the user's approve/deny decision from the review window:
    /// approved rows join `rows` for export, the rest are written to
    /// `followUpReport` instead of being silently dropped. `reviewRows` is
    /// left empty afterward -- this consumes the decision, so calling it a
    /// second time (e.g. by mistake, on a result with no review rows left)
    /// is a harmless no-op.
    public func resolvingReviewRows(approved: Set<Int>) -> ConversionResult {
        guard !reviewRows.isEmpty else { return self }
        var result = self
        var deniedRows: [[String: String]] = []
        for review in reviewRows {
            if approved.contains(review.rowNumber) {
                result.rows.append(review.output)
            } else {
                deniedRows.append(review.output)
            }
        }
        if !deniedRows.isEmpty {
            result.followUpReport = FollowUpReport(
                title: "Rows Needing Review", columns: result.columns, rows: deniedRows)
        }
        result.reviewRows = []
        return result
    }

    /// Problems grouped by spreadsheet row, in the order they appear in the
    /// file. One row can fail for several reasons (a blank ID *and* a blank
    /// reading level), and the review window lists a row once, not twice.
    public var issues: [RowIssue] { Self.group(errors) }

    /// Notices grouped the same way as `issues`, but never block the export.
    public var noticeIssues: [RowIssue] { Self.group(notices) }

    public var hasNotices: Bool { !notices.isEmpty }

    /// How many rows would be left out if the user chooses to skip them.
    /// Notices never contribute to this -- they do not block anything.
    public var skippedRowCount: Int { issues.count }

    private static func group(_ items: [RowError]) -> [RowIssue] {
        var order: [Int] = []
        var byRow: [Int: [String]] = [:]
        for item in items {
            if byRow[item.rowNumber] == nil { order.append(item.rowNumber) }
            byRow[item.rowNumber, default: []].append(item.message)
        }
        return order.map { RowIssue(rowNumber: $0, problems: byRow[$0] ?? []) }
    }

    /// The problem list as text, for copying out or pasting into an email.
    public func issuesReport() -> String {
        issues.map(\.description).joined(separator: "\n")
    }

    public func noticesReport() -> String {
        noticeIssues.map(\.description).joined(separator: "\n")
    }

    /// Notices and problems together, for the review window's "Copy List" button.
    public func fullReport() -> String {
        var parts: [String] = []
        if hasNotices { parts.append("Benchmark notices:\n" + noticesReport()) }
        if !issues.isEmpty { parts.append("Problems:\n" + issuesReport()) }
        return parts.joined(separator: "\n\n")
    }
}

/// Everything wrong with one row of the source file.
public struct RowIssue: Equatable {
    public let rowNumber: Int
    public let problems: [String]

    public init(rowNumber: Int, problems: [String]) {
        self.rowNumber = rowNumber
        self.problems = problems
    }

    public var summary: String { problems.joined(separator: " ") }
    public var description: String { "Row \(rowNumber): \(summary)" }
}

/// What every assessment converter provides.
///
/// The app shell (file picking, prompts, column matching, CSV export) is written
/// against this protocol only, so a second assessment type is a new type here --
/// not a change to the UI.
public protocol AssessmentConverter {
    var key: String { get }
    var displayName: String { get }
    var summary: String { get }
    var prompts: [PromptField] { get }
    var sourceColumns: [SourceColumn] { get }
    var outputColumns: [String] { get }

    /// Map `table` into output rows. `columns` maps each `SourceColumn` key to
    /// the header holding it -- auto-matched, or confirmed by the user.
    func convert(
        table: Table, answers: [String: String], columns: [String: String?]
    ) throws -> ConversionResult

    func defaultOutputName(answers: [String: String]) -> String

    /// Load `url` into the `Table` this converter maps columns against. The
    /// default reads it as a plain spreadsheet (one header row, one record per
    /// row); a converter whose source isn't shaped that way -- a block per
    /// teacher rather than one row per student, say -- overrides this to do
    /// its own parsing instead.
    func loadSource(at url: URL) throws -> Table

    /// The naming pattern offered for this assessment; the user can change it.
    var defaultFileNameTemplate: String { get }

    /// Converter-specific rules a column mapping must satisfy, beyond "every
    /// required column is filled in" -- for example "the name has to arrive
    /// either as one combined column or as a first/last pair".
    func problems(for mapping: ColumnMapping) -> [String]

    /// A short description of any scoring table this batch will apply -- e.g.
    /// which year's benchmark rubric -- shown so the user can see what is about
    /// to be applied before converting. `nil` when the converter has no such
    /// table (the default) or the answers given so far don't yet determine one.
    func scoringTableSummary(for answers: [String: String]) -> ScoringTableSummary?

    /// Rows in `table` that represent the same real submission more than
    /// once -- e.g. one student's assignment duplicated across two class
    /// rosters -- grouped by whatever this converter considers "the same".
    /// Each inner array holds 0-based indices into `table.rows`; empty for a
    /// converter that never needs this (the default) or a table with no
    /// duplicates this time.
    func duplicateGroups(in table: Table) -> [[Int]]

    /// The columns (by header name) shown per candidate row in the duplicate
    /// picker, so the user can tell the copies apart -- e.g. Class, Score.
    var duplicatePickerColumns: [String] { get }

    /// A short label identifying the student a duplicate group belongs to,
    /// e.g. "Castro, Delila" -- shown once per group in the picker.
    func duplicateGroupLabel(for table: Table, firstRowIndex: Int) -> String
}

/// What `scoringTableSummary(for:)` reports about the table in effect.
public struct ScoringTableSummary {
    /// e.g. "Benchmark: English 2026-27 · Grades K-5"
    public let text: String
    /// True when a dated table was carried forward for a later year than it was
    /// built for, because nothing newer has been loaded.
    public let isCarriedForward: Bool
    /// Shown alongside `text` only when `isCarriedForward` is true, e.g.
    /// "no table for 2028-2029 yet".
    public let carriedForwardNote: String?

    public init(text: String, isCarriedForward: Bool = false, carriedForwardNote: String? = nil) {
        self.text = text
        self.isCarriedForward = isCarriedForward
        self.carriedForwardNote = carriedForwardNote
    }
}

extension AssessmentConverter {
    public func problems(for mapping: ColumnMapping) -> [String] { [] }

    public func loadSource(at url: URL) throws -> Table { try Pipeline.loadSource(at: url) }

    public func scoringTableSummary(for answers: [String: String]) -> ScoringTableSummary? { nil }

    public func duplicateGroups(in table: Table) -> [[Int]] { [] }

    public var duplicatePickerColumns: [String] { [] }

    public func duplicateGroupLabel(for table: Table, firstRowIndex: Int) -> String { "" }

    public var defaultFileNameTemplate: String { "{assessment}_{window}_{year}_educlimber" }

    /// Token names this converter understands, for the file-name help text.
    public var fileNameTokens: [String] {
        FileNameTemplate.generalTokens + prompts.map(\.key) + ["window", "year"]
    }
}
