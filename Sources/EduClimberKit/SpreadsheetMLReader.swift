import Foundation

/// Reads Excel 2003 "XML Spreadsheet" files (`<Workbook>` / `<Row>` / `<Cell>`).
///
/// Another shape that arrives named `.xls`: plain XML rather than the binary
/// format, so it can be read directly.
public enum SpreadsheetMLReader {
    public static func read(contentsOf url: URL) throws -> Table {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SourceFileError.unreadable(error.localizedDescription)
        }
        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse(), !collector.grid.isEmpty else {
            throw SourceFileError.malformedTable("no rows were found in this XML spreadsheet")
        }
        return try makeTable(fromGrid: collector.grid)
    }
}

private final class Collector: NSObject, XMLParserDelegate {
    private(set) var grid: [[String]] = []
    private var row: [String] = []
    private var value = ""
    private var insideData = false
    private var cellIndex: Int?
    private var finishedFirstTable = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch local(elementName, qualifiedName) {
        case "row":
            row = []
            // ss:Index on a Row skips blank rows; keep them so row numbers match.
            if let index = attributes["ss:Index"].flatMap(Int.init) {
                while grid.count < index - 1 { grid.append([]) }
            }
        case "cell":
            // ss:Index on a Cell means "this is column N" -- Excel omits empties.
            cellIndex = attributes["ss:Index"].flatMap(Int.init).map { $0 - 1 }
            value = ""
        case "data":
            insideData = true
            value = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideData { value += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch local(elementName, qualifiedName) {
        case "data":
            insideData = false
        case "cell":
            if let index = cellIndex {
                while row.count < index { row.append("") }
            }
            row.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
            cellIndex = nil
            value = ""
        case "row":
            grid.append(row)
            row = []
        case "table":
            finishedFirstTable = true  // only the first worksheet is read
            if finishedFirstTable { parser.abortParsing() }
        default:
            break
        }
    }

    /// Element names arrive with or without the `ss:` prefix depending on how
    /// the file declares its namespaces.
    private func local(_ elementName: String, _ qualifiedName: String?) -> String {
        let name = elementName.isEmpty ? (qualifiedName ?? "") : elementName
        return name.split(separator: ":").last.map(String.init)?.lowercased() ?? ""
    }
}
