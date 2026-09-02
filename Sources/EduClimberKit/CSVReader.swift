import Foundation

/// RFC 4180-style CSV parsing: quoted fields, doubled quotes, embedded newlines.
public enum CSVReader {
    public static func read(contentsOf url: URL) throws -> Table {
        let text = try readText(url)
        let delimiter = detectDelimiter(in: text)
        return try makeTable(fromGrid: parse(text, delimiter: delimiter))
    }

    static func readText(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SourceFileError.unreadable(error.localizedDescription)
        }
        if let text = String(data: data, encoding: .utf8) {
            return stripBOM(text)
        }
        // Exports from older systems are often Windows-1252 rather than UTF-8.
        if let text = String(data: data, encoding: .windowsCP1252) {
            return stripBOM(text)
        }
        throw SourceFileError.unreadable("the text encoding was not recognized")
    }

    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// Pick the delimiter that yields the most columns on the first line.
    static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.prefix(while: { $0 != "\n" && $0 != "\r" })
        let candidates: [Character] = [",", ";", "\t", "|"]
        var best: Character = ","
        var bestCount = 0
        for candidate in candidates {
            let count = parse(String(firstLine), delimiter: candidate).first?.count ?? 0
            if count > bestCount {
                bestCount = count
                best = candidate
            }
        }
        return best
    }

    public static func parse(_ text: String, delimiter: Character = ",") -> [[String]] {
        var grid: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            grid.append(row)
            row = []
        }

        while true {
            let character: Character
            if let held = pending {
                character = held
                pending = nil
            } else if let next = iterator.next() {
                character = next
            } else {
                break
            }

            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")  // an escaped quote inside a field
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"":
                inQuotes = true
            case delimiter:
                endField()
            // Swift treats CRLF as one Character (a single grapheme cluster), so
            // Windows line endings must be matched as "\r\n", not as "\r" then "\n".
            case "\r\n", "\r", "\n":
                endRow()
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return grid
    }
}
