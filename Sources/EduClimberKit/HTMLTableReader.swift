import Foundation

/// Reads an HTML `<table>` export.
///
/// Plenty of web systems produce a file named `.xls` that is really an HTML
/// page with one table in it -- Excel opens those happily, so nobody notices
/// until another program tries to read one.
public enum HTMLTableReader {
    public static func read(contentsOf url: URL) throws -> Table {
        let text = try CSVReader.readText(url)
        let grid = parse(text)
        guard !grid.isEmpty else {
            throw SourceFileError.malformedTable(
                "no table rows were found in this HTML file")
        }
        return try makeTable(fromGrid: grid)
    }

    /// Rows of the richest table in the document (exports sometimes wrap the
    /// data table in layout tables, so the one with the most rows wins).
    public static func parse(_ html: String) -> [[String]] {
        let tables = splitTables(html)
        var best: [[String]] = []
        for table in tables {
            let rows = rowsIn(table)
            if rows.count > best.count { best = rows }
        }
        return best
    }

    private static func splitTables(_ html: String) -> [String] {
        // Nested tables are handled by treating every <table ...> opening as the
        // start of a candidate that runs to the next </table>.
        var tables: [String] = []
        var search = html.startIndex..<html.endIndex
        while let open = html.range(of: "<table", options: [.caseInsensitive], range: search) {
            let after = open.upperBound
            let close = html.range(
                of: "</table", options: [.caseInsensitive], range: after..<html.endIndex)
            let end = close?.lowerBound ?? html.endIndex
            tables.append(String(html[after..<end]))
            search = after..<html.endIndex
            if close == nil { break }
        }
        return tables.isEmpty ? [html] : tables
    }

    private static func rowsIn(_ table: String) -> [[String]] {
        var rows: [[String]] = []
        for chunk in splitOnTag(table, tag: "tr") {
            let cells = splitOnTag(chunk, tag: "td") + splitOnTag(chunk, tag: "th")
            guard !cells.isEmpty else { continue }
            // Keep document order when a row mixes <th> and <td>.
            let ordered = orderedCells(in: chunk)
            rows.append(ordered.map(clean))
        }
        return rows
    }

    private static func orderedCells(in row: String) -> [String] {
        var cells: [String] = []
        var index = row.startIndex
        while index < row.endIndex {
            guard let open = nextCellTag(in: row, from: index) else { break }
            guard let contentStart = row.range(of: ">", range: open.upperBound..<row.endIndex) else {
                break
            }
            let closeRange = row.range(
                of: "</t", options: [.caseInsensitive],
                range: contentStart.upperBound..<row.endIndex)
            let nextOpen = nextCellTag(in: row, from: contentStart.upperBound)
            let end = [closeRange?.lowerBound, nextOpen?.lowerBound]
                .compactMap { $0 }.min() ?? row.endIndex
            cells.append(String(row[contentStart.upperBound..<end]))
            index = end
        }
        return cells
    }

    private static func nextCellTag(in row: String, from: String.Index) -> Range<String.Index>? {
        let td = row.range(of: "<td", options: [.caseInsensitive], range: from..<row.endIndex)
        let th = row.range(of: "<th", options: [.caseInsensitive], range: from..<row.endIndex)
        return [td, th].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
    }

    private static func splitOnTag(_ text: String, tag: String) -> [String] {
        var parts: [String] = []
        var search = text.startIndex..<text.endIndex
        while let open = text.range(
            of: "<\(tag)", options: [.caseInsensitive], range: search) {
            let rest = open.upperBound..<text.endIndex
            guard let contentStart = text.range(of: ">", range: rest) else { break }
            let close = text.range(
                of: "</\(tag)", options: [.caseInsensitive],
                range: contentStart.upperBound..<text.endIndex)
            let end = close?.lowerBound ?? text.endIndex
            parts.append(String(text[contentStart.upperBound..<end]))
            search = (close?.upperBound ?? text.endIndex)..<text.endIndex
            if close == nil { break }
        }
        return parts
    }

    /// Strip inner markup and turn entities back into characters.
    static func clean(_ cell: String) -> String {
        var text = cell.replacingOccurrences(
            of: "<br[^>]*>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = [
            "&nbsp;": "\u{00A0}", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&#x27;": "'",
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(
                of: entity, with: replacement, options: .caseInsensitive)
        }
        // Remaining numeric entities, decimal and hex.
        let pattern = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);")
        guard let pattern else { return result }
        let full = NSRange(result.startIndex..., in: result)
        var output = ""
        var last = result.startIndex
        for match in pattern.matches(in: result, range: full) {
            guard let range = Range(match.range, in: result),
                  let hexFlag = Range(match.range(at: 1), in: result),
                  let digits = Range(match.range(at: 2), in: result) else { continue }
            let radix = result[hexFlag].isEmpty ? 10 : 16
            output += result[last..<range.lowerBound]
            if let value = UInt32(result[digits], radix: radix),
               let scalar = Unicode.Scalar(value) {
                output.append(Character(scalar))
            }
            last = range.upperBound
        }
        output += result[last...]
        return output
    }
}
