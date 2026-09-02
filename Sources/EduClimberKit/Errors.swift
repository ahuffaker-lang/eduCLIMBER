import Foundation

/// The file could not be read at all.
public enum SourceFileError: LocalizedError, Equatable {
    case empty
    case unreadable(String)
    case unsupportedType(String)
    case legacyExcel
    case malformedExcel(String)
    case malformedTable(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The file appears to be empty — no header row found."
        case .unreadable(let detail):
            return "Could not open the file: \(detail)"
        case .unsupportedType(let ext):
            let named = ext.isEmpty ? "This file" : "A '.\(ext)' file"
            return "\(named) is not a spreadsheet this app can read. "
                + "Export the assessment data as Excel (.xlsx) or CSV and try again."
        case .legacyExcel:
            return "This is an Excel 97-2003 workbook (the old binary .xls format), "
                + "which this app cannot read.\nOpen it in Excel and choose "
                + "File > Save As > Excel Workbook (.xlsx), or Save As > CSV, then "
                + "convert that file."
        case .malformedTable(let detail):
            return "This file looked like a table but could not be read (\(detail)). "
                + "Re-saving it from Excel as .xlsx or .csv usually fixes it."
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
