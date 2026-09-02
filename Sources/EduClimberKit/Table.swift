import Foundation

/// A source spreadsheet loaded into memory.
///
/// Headers are matched loosely: case, punctuation and spacing are ignored, so
/// `reading_level` and `READING LEVEL (A-Z)` both find the same column.
public struct Table {
    public var headers: [String]
    public var rows: [[String: String]]
    /// 1-based spreadsheet row number of the first data row (the header is row 1
    /// unless the export starts with blank padding rows).
    public var firstDataRowNumber: Int

    public init(headers: [String], rows: [[String: String]], firstDataRowNumber: Int = 2) {
        self.headers = headers
        self.rows = rows
        self.firstDataRowNumber = firstDataRowNumber
    }

    /// The spreadsheet row number of the data row at `index`, for error messages.
    public func rowNumber(_ index: Int) -> Int {
        firstDataRowNumber + index
    }

    /// The real header matching any of `candidates`, or nil.
    public func findColumn(_ candidates: [String]) -> String? {
        var byNormalized: [String: String] = [:]
        for header in headers where byNormalized[normalizeHeader(header)] == nil {
            byNormalized[normalizeHeader(header)] = header
        }
        let wanted = candidates.map(normalizeHeader)
        for name in wanted {
            if let header = byNormalized[name] { return header }
        }
        // Containment, so "Student ID Number" still matches "Student ID". Short
        // names ("id", "grade") are skipped -- they turn up inside unrelated
        // headers and match the wrong column.
        for name in wanted where name.count >= 8 {
            for header in headers {
                let normalized = normalizeHeader(header)
                if normalized.contains(name) || name.contains(normalized) { return header }
            }
        }
        return nil
    }

    public func value(_ row: [String: String], _ column: String?) -> String {
        guard let column, let raw = row[column] else { return "" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Fold a header down to comparable letters and digits.
public func normalizeHeader(_ header: String) -> String {
    String(header.lowercased().unicodeScalars.filter { scalar in
        CharacterSet.alphanumerics.contains(scalar)
    }.map(Character.init))
}

/// Build a table from a raw grid, skipping leading blank rows and blank spacers.
public func makeTable(fromGrid grid: [[String]]) throws -> Table {
    guard let headerIndex = grid.firstIndex(where: { row in
        row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }) else {
        throw SourceFileError.empty
    }

    let headers = deduplicate(grid[headerIndex].map { $0.trimmingCharacters(in: .whitespaces) })
    var rows: [[String: String]] = []
    for raw in grid[(headerIndex + 1)...] {
        let values = raw.map { $0.trimmingCharacters(in: .whitespaces) }
        if values.allSatisfy({ $0.isEmpty }) { continue }
        var row: [String: String] = [:]
        for (position, header) in headers.enumerated() {
            row[header] = position < values.count ? values[position] : ""
        }
        rows.append(row)
    }
    return Table(headers: headers, rows: rows, firstDataRowNumber: headerIndex + 2)
}

/// Give every column a unique, non-empty name.
func deduplicate(_ headers: [String]) -> [String] {
    var seen: [String: Int] = [:]
    var result: [String] = []
    for (position, header) in headers.enumerated() {
        var name = header.isEmpty ? "Column \(position + 1)" : header
        if let count = seen[name] {
            seen[name] = count + 1
            name = "\(name) (\(count + 1))"
        } else {
            seen[name] = 1
        }
        result.append(name)
    }
    return result
}
