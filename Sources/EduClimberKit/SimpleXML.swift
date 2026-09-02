import Foundation

/// Small XMLParser helpers for the handful of parts an .xlsx export needs.
enum SimpleXML {
    /// Attributes of every element with the given name, in document order.
    static func elements(in data: Data, named name: String) -> [[String: String]] {
        let collector = ElementCollector(name: name)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.found
    }

    /// The workbook's shared string table, one entry per <si>.
    static func sharedStrings(in data: Data) -> [String] {
        let collector = SharedStringCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.strings
    }

    /// The worksheet as a grid of strings, with blank rows and gaps preserved so
    /// row numbers still line up with what the user sees in Excel.
    static func sheetGrid(in data: Data, sharedStrings: [String]) -> [[String]] {
        let collector = SheetCollector(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.grid
    }
}

private final class ElementCollector: NSObject, XMLParserDelegate {
    let name: String
    var found: [[String: String]] = []

    init(name: String) { self.name = name }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        // Compare on the qualified name too: workbook parts use r:id, and the
        // element itself may or may not carry a namespace prefix.
        if elementName == name || qualifiedName == name {
            found.append(attributes)
        }
    }
}

private final class SharedStringCollector: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var insideItem = false
    private var insideText = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "si":
            insideItem = true
            current = ""
        case "t":
            insideText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem && insideText { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "si":
            strings.append(current)
            insideItem = false
        case "t":
            insideText = false
        default:
            break
        }
    }
}

private final class SheetCollector: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private(set) var grid: [[String]] = []

    private var row: [String] = []
    private var expectedRowNumber = 1
    private var cellIndex = 0
    private var cellType = ""
    private var value = ""
    private var insideValue = false
    private var insideInlineText = false

    init(sharedStrings: [String]) {
        self.sharedStrings = sharedStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "row":
            row = []
            if let reference = attributes["r"], let number = Int(reference) {
                // Excel omits empty rows; re-insert them so row numbers match.
                while expectedRowNumber < number {
                    grid.append([])
                    expectedRowNumber += 1
                }
            }
        case "c":
            cellType = attributes["t"] ?? ""
            value = ""
            cellIndex = attributes["r"].map(XLSXReader.columnIndex(fromReference:)) ?? row.count
        case "v":
            insideValue = true
        case "t":
            insideInlineText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideValue || insideInlineText { value += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "v":
            insideValue = false
        case "t":
            insideInlineText = false
        case "c":
            while row.count < cellIndex { row.append("") }
            row.append(resolve())
        case "row":
            grid.append(row)
            expectedRowNumber += 1
            row = []
        default:
            break
        }
    }

    /// Turn a raw cell value into display text.
    private func resolve() -> String {
        switch cellType {
        case "s":
            guard let index = Int(value), sharedStrings.indices.contains(index) else { return "" }
            return sharedStrings[index]
        case "inlineStr", "str":
            return value
        case "b":
            return value == "1" ? "TRUE" : "FALSE"
        default:
            return XLSXReader.formatNumber(value)
        }
    }
}
