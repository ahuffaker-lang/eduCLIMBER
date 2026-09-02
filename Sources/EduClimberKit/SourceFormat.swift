import Foundation

/// What a file actually is, judged by its first bytes rather than its name.
///
/// Assessment systems label their exports loosely: a file called `.xls` is
/// often an HTML table or an XML spreadsheet, and a file with no extension at
/// all may be a perfectly good CSV. Sniffing the content means the app accepts
/// what the user was given instead of arguing about the file name.
public enum SourceFormat: Equatable {
    case xlsx            // a real .xlsx/.xlsm (a ZIP of XML)
    case spreadsheetML   // Excel 2003 "XML Spreadsheet"
    case htmlTable       // an HTML <table>, which many web exports call .xls
    case delimitedText   // CSV, TSV, anything delimited
    case legacyExcel     // Excel 97-2003 binary (.xls)
    case pdf
    case unknown(String)

    /// Bytes to read before deciding; enough for any signature or opening tag.
    static let sniffLength = 8192

    public static func detect(at url: URL) throws -> SourceFormat {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw SourceFileError.unreadable(error.localizedDescription)
        }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: sniffLength)
        return detect(head: head, fileExtension: url.pathExtension.lowercased())
    }

    static func detect(head: Data, fileExtension: String) -> SourceFormat {
        if head.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return .xlsx }  // "PK\u{3}\u{4}"
        // Compound File Binary: Excel 97-2003, and also .doc/.ppt of that era.
        if head.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
            return .legacyExcel
        }
        if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }  // "%PDF"

        guard let text = decodeText(head) else {
            return .unknown(fileExtension)
        }
        let start = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let lowered = start.lowercased()

        if lowered.contains("urn:schemas-microsoft-com:office:spreadsheet") {
            return .spreadsheetML
        }
        if lowered.hasPrefix("<!doctype html") || lowered.hasPrefix("<html")
            || lowered.hasPrefix("<table") || lowered.contains("<table") {
            return .htmlTable
        }
        return .delimitedText
    }

    static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        // A truncated multi-byte character at the sniff boundary is not a
        // reason to give up on the file.
        for trim in 1...3 where data.count > trim {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .windowsCP1252)
    }
}
