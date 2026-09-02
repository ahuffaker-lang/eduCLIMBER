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
}
