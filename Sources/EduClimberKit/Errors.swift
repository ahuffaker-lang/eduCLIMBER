import Foundation

/// The file could not be read at all.
public enum SourceFileError: LocalizedError, Equatable {
    case empty
    case unreadable(String)
    case unsupportedType(String)
    case legacyExcel
    case malformedExcel(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The file appears to be empty — no header row found."
        case .unreadable(let detail):
            return "Could not open the file: \(detail)"
        case .unsupportedType(let ext):
            return "Unsupported file type '\(ext)'. Use a .csv or .xlsx file."
        case .legacyExcel:
            return "Legacy .xls files are not supported. Please re-save the export "
                + "as .xlsx or .csv and try again."
        case .malformedExcel(let detail):
            return "This .xlsx file could not be read (\(detail)). "
                + "Re-saving it from Excel as .xlsx or .csv usually fixes it."
        }
    }
}

/// A problem with the batch as a whole: bad prompt answers, unmatched columns.
public struct ConverterError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
