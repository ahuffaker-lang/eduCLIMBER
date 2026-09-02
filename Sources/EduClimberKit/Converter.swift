import Foundation

/// One value the user supplies for a whole batch.
public struct PromptField {
    public enum Kind {
        case choice([String])
        case text(pattern: String)
    }

    public let key: String
    public let label: String
    public let kind: Kind
    public let help: String
    public let placeholder: String

    public init(key: String, label: String, kind: Kind, help: String = "", placeholder: String = "") {
        self.key = key
        self.label = label
        self.kind = kind
        self.help = help
        self.placeholder = placeholder
    }

    public var choices: [String] {
        if case .choice(let options) = kind { return options }
        return []
    }

    /// An error message, or nil when the value is acceptable.
    public func validate(_ value: String?) -> String? {
        let value = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "\(label) is required." }
        switch kind {
        case .choice(let options):
            guard options.contains(value) else {
                return "\(label) must be one of: \(options.joined(separator: ", "))."
            }
        case .text(let pattern):
            guard value.range(of: pattern, options: .regularExpression) != nil else {
                return help.isEmpty ? "\(label) is not in the expected format." : help
            }
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

public struct ConversionResult {
    public var columns: [String]
    public var rows: [[String: String]]
    public var errors: [RowError]

    public init(columns: [String], rows: [[String: String]] = [], errors: [RowError] = []) {
        self.columns = columns
        self.rows = rows
        self.errors = errors
    }

    public var isClean: Bool { errors.isEmpty }

    /// Rows that converted and can be exported.
    public var hasUsableRows: Bool { !rows.isEmpty }

    /// Problems grouped by spreadsheet row, in the order they appear in the
    /// file. One row can fail for several reasons (a blank ID *and* a blank
    /// reading level), and the review window lists a row once, not twice.
    public var issues: [RowIssue] {
        var order: [Int] = []
        var problemsByRow: [Int: [String]] = [:]
        for error in errors {
            if problemsByRow[error.rowNumber] == nil { order.append(error.rowNumber) }
            problemsByRow[error.rowNumber, default: []].append(error.message)
        }
        return order.map { RowIssue(rowNumber: $0, problems: problemsByRow[$0] ?? []) }
    }

    /// How many rows would be left out if the user chooses to skip them.
    public var skippedRowCount: Int { issues.count }

    /// The issue list as text, for copying out or pasting into an email.
    public func issuesReport() -> String {
        issues.map(\.description).joined(separator: "\n")
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

    /// Converter-specific rules a column mapping must satisfy, beyond "every
    /// required column is filled in" -- for example "the name has to arrive
    /// either as one combined column or as a first/last pair".
    func problems(for mapping: ColumnMapping) -> [String]
}

extension AssessmentConverter {
    public func problems(for mapping: ColumnMapping) -> [String] { [] }
}
