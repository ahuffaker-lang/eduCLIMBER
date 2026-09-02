import Foundation

public enum CSVWriter {
    /// Render rows with exactly `columns`, in order.
    public static func text(columns: [String], rows: [[String: String]]) -> String {
        var lines = [columns.map(escape).joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { escape(row[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Write the CSV to disk.
    ///
    /// Plain UTF-8 with no byte-order mark: a BOM would land inside the first
    /// header name ("Assessment Group") when eduCLIMBER's importer parses it.
    public static func write(columns: [String], rows: [[String: String]], to url: URL) throws {
        let payload = text(columns: columns, rows: rows)
        guard let data = payload.data(using: .utf8) else {
            throw ConverterError("The converted data could not be encoded as UTF-8.")
        }
        try data.write(to: url, options: .atomic)
    }

    static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(",") || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
