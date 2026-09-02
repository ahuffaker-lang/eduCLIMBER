import Foundation

/// Reads an Excel 97-2003 workbook (BIFF8) -- the old binary `.xls`.
///
/// Assessment systems still export this format, so the app reads it rather than
/// asking for a re-save. Only what a data export needs is handled: the first
/// worksheet's text, numbers and shared strings.
public enum XLSReader {
    // Record types, from the BIFF8 specification.
    private enum Record {
        static let formula: UInt16 = 0x0006
        static let eof: UInt16 = 0x000A
        static let filePass: UInt16 = 0x002F
        static let continueRecord: UInt16 = 0x003C
        static let sst: UInt16 = 0x00FC
        static let boundSheet: UInt16 = 0x0085
        static let mulRK: UInt16 = 0x00BD
        static let mulBlank: UInt16 = 0x00BE
        static let blank: UInt16 = 0x0201
        static let number: UInt16 = 0x0203
        static let label: UInt16 = 0x0204
        static let boolErr: UInt16 = 0x0205
        static let string: UInt16 = 0x0207
        static let rk: UInt16 = 0x027E
        static let labelSST: UInt16 = 0x00FD
        static let bof: UInt16 = 0x0809
    }

    struct RawRecord {
        var id: UInt16
        var body: [UInt8]
        var offset: Int
    }

    public static func read(contentsOf url: URL) throws -> Table {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SourceFileError.unreadable(error.localizedDescription)
        }
        let container = try CompoundFile(data: data)
        // Excel 97+ calls it "Workbook"; Excel 5/95 used "Book".
        let name = container.streams["Workbook"] != nil ? "Workbook" : "Book"
        let stream = try container.stream(named: name)
        let grid = try grid(fromWorkbook: stream)
        return try makeTable(fromGrid: grid)
    }

    static func grid(fromWorkbook stream: [UInt8]) throws -> [[String]] {
        let records = split(stream)
        if records.contains(where: { $0.id == Record.filePass }) {
            throw SourceFileError.encryptedWorkbook
        }

        let strings = sharedStrings(in: records)
        let sheetStart = firstWorksheetOffset(in: records)
        let sheetRecords = sheetStart.map { start in
            split(stream, from: start)
        } ?? records

        var cells: [Int: [Int: String]] = [:]
        var lastLabelPosition: (row: Int, column: Int)?

        for record in sheetRecords {
            let body = record.body
            switch record.id {
            case Record.eof where !cells.isEmpty:
                // End of the first worksheet; later sheets are ignored.
                return assemble(cells)
            case Record.labelSST:
                let index = Int(CompoundFile.uint32(body, 6))
                let text = strings.indices.contains(index) ? strings[index] : ""
                put(&cells, body, text)
            case Record.label:
                let text = readString(body, at: 6, richTextAllowed: true).value
                put(&cells, body, text)
            case Record.number:
                let bits = uint64(body, 6)
                put(&cells, body, XLSXReader.formatNumber(String(Double(bitPattern: bits))))
            case Record.rk:
                put(&cells, body, decodeRK(CompoundFile.uint32(body, 6)))
            case Record.mulRK:
                let row = Int(CompoundFile.uint16(body, 0))
                let first = Int(CompoundFile.uint16(body, 2))
                var index = 4
                var column = first
                while index + 6 <= body.count - 2 {
                    let value = decodeRK(CompoundFile.uint32(body, index + 2))
                    cells[row, default: [:]][column] = value
                    column += 1
                    index += 6
                }
            case Record.boolErr:
                let value = body.count > 6 && body[6] != 0 ? "TRUE" : "FALSE"
                put(&cells, body, body.count > 7 && body[7] == 1 ? "" : value)
            case Record.formula:
                // A formula that produced text is followed by a STRING record.
                lastLabelPosition = (Int(CompoundFile.uint16(body, 0)),
                                     Int(CompoundFile.uint16(body, 2)))
                let bits = uint64(body, 6)
                if (bits >> 48) != 0xFFFF {
                    put(&cells, body, XLSXReader.formatNumber(String(Double(bitPattern: bits))))
                    lastLabelPosition = nil
                }
            case Record.string:
                if let position = lastLabelPosition {
                    let text = readString(body, at: 0, richTextAllowed: true).value
                    cells[position.row, default: [:]][position.column] = text
                    lastLabelPosition = nil
                }
            case Record.blank, Record.mulBlank:
                break  // nothing to store; gaps are filled in when assembling
            default:
                break
            }
        }
        return assemble(cells)
    }

    // MARK: - Records

    static func split(_ stream: [UInt8], from start: Int = 0) -> [RawRecord] {
        var records: [RawRecord] = []
        var index = start
        while index + 4 <= stream.count {
            let id = CompoundFile.uint16(stream, index)
            let length = Int(CompoundFile.uint16(stream, index + 2))
            let bodyStart = index + 4
            let bodyEnd = bodyStart + length
            guard bodyEnd <= stream.count else { break }
            records.append(
                RawRecord(id: id, body: Array(stream[bodyStart..<bodyEnd]), offset: index))
            index = bodyEnd
        }
        return records
    }

    /// Where the first worksheet's records begin, per the BOUNDSHEET entries.
    static func firstWorksheetOffset(in records: [RawRecord]) -> Int? {
        for record in records where record.id == Record.boundSheet {
            let type = record.body.count > 5 ? record.body[5] : 0xFF
            let hidden = record.body.count > 4 ? record.body[4] : 0
            guard type == 0, hidden == 0 else { continue }  // 0 = worksheet, visible
            return Int(CompoundFile.uint32(record.body, 0))
        }
        return nil
    }

    /// The shared string table, which spans SST plus any CONTINUE records.
    static func sharedStrings(in records: [RawRecord]) -> [String] {
        guard let sstIndex = records.firstIndex(where: { $0.id == Record.sst }) else { return [] }
        var blocks: [[UInt8]] = [records[sstIndex].body]
        var index = sstIndex + 1
        while index < records.count, records[index].id == Record.continueRecord {
            blocks.append(records[index].body)
            index += 1
        }

        let unique = Int(CompoundFile.uint32(blocks[0], 4))
        var reader = BlockReader(blocks: blocks, position: 8)
        var strings: [String] = []
        strings.reserveCapacity(max(0, min(unique, 1_000_000)))
        for _ in 0..<max(0, unique) {
            guard let text = reader.readString() else { break }
            strings.append(text)
        }
        return strings
    }

    // MARK: - Values

    /// RK values pack a number into four bytes, sometimes scaled by 100.
    static func decodeRK(_ raw: UInt32) -> String {
        let isInteger = raw & 0x02 != 0
        let isScaled = raw & 0x01 != 0
        var value: Double
        if isInteger {
            value = Double(Int32(bitPattern: raw) >> 2)
        } else {
            let bits = UInt64(raw & 0xFFFF_FFFC) << 32
            value = Double(bitPattern: bits)
        }
        if isScaled { value /= 100 }
        return XLSXReader.formatNumber(String(value))
    }

    private static func put(_ cells: inout [Int: [Int: String]], _ body: [UInt8], _ value: String) {
        let row = Int(CompoundFile.uint16(body, 0))
        let column = Int(CompoundFile.uint16(body, 2))
        cells[row, default: [:]][column] = value
    }

    /// Fill the sparse cell map into a rectangular grid, keeping row positions
    /// so a blank row in Excel stays a blank row here.
    private static func assemble(_ cells: [Int: [Int: String]]) -> [[String]] {
        guard let lastRow = cells.keys.max() else { return [] }
        var grid: [[String]] = []
        grid.reserveCapacity(lastRow + 1)
        for row in 0...lastRow {
            guard let columns = cells[row], let lastColumn = columns.keys.max() else {
                grid.append([])
                continue
            }
            var line = [String](repeating: "", count: lastColumn + 1)
            for (column, value) in columns where column <= lastColumn {
                line[column] = value
            }
            grid.append(line)
        }
        return grid
    }

    private static func uint64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        guard offset + 8 <= bytes.count else { return 0 }
        var value: UInt64 = 0
        for index in (0..<8).reversed() {
            value = value << 8 | UInt64(bytes[offset + index])
        }
        return value
    }

    /// Read one BIFF8 string starting at `offset` in a single record body.
    static func readString(
        _ body: [UInt8], at offset: Int, richTextAllowed: Bool
    ) -> (value: String, next: Int) {
        var reader = BlockReader(blocks: [body], position: offset)
        let text = reader.readString() ?? ""
        return (text, reader.position)
    }
}

/// Reads BIFF8 strings that may run across CONTINUE record boundaries.
///
/// The awkward part of the format: a string can be cut in half between records,
/// and the second half starts with a fresh flag byte saying whether the rest is
/// 8-bit or 16-bit text.
struct BlockReader {
    let blocks: [[UInt8]]
    private var blockIndex = 0
    private(set) var position: Int

    init(blocks: [[UInt8]], position: Int) {
        self.blocks = blocks
        self.position = position
    }

    private var current: [UInt8] { blocks[blockIndex] }

    private mutating func advanceBlockIfNeeded() -> Bool {
        while blockIndex < blocks.count, position >= blocks[blockIndex].count {
            blockIndex += 1
            position = 0
        }
        return blockIndex < blocks.count
    }

    private mutating func byte() -> UInt8? {
        guard advanceBlockIfNeeded() else { return nil }
        let value = current[position]
        position += 1
        return value
    }

    private mutating func word() -> UInt16? {
        guard let low = byte(), let high = byte() else { return nil }
        return UInt16(low) | UInt16(high) << 8
    }

    private mutating func doubleWord() -> UInt32? {
        guard let low = word(), let high = word() else { return nil }
        return UInt32(low) | UInt32(high) << 16
    }

    mutating func readString() -> String? {
        guard let characterCount = word(), let flags = byte() else { return nil }
        var wide = flags & 0x01 != 0
        let hasRichText = flags & 0x08 != 0
        let hasFarEast = flags & 0x04 != 0

        var runCount = 0
        var farEastBytes = 0
        if hasRichText { runCount = Int(word() ?? 0) }
        if hasFarEast { farEastBytes = Int(doubleWord() ?? 0) }

        var scalars: [UInt16] = []
        scalars.reserveCapacity(Int(characterCount))
        var remaining = Int(characterCount)
        while remaining > 0 {
            guard advanceBlockIfNeeded() else { break }
            if position == 0, blockIndex > 0, scalars.count < Int(characterCount) {
                // A continuation block restates the width for the remainder.
                if let continuationFlags = byte() {
                    wide = continuationFlags & 0x01 != 0
                }
            }
            let available = current.count - position
            if available <= 0 { continue }
            if wide {
                let readable = min(remaining, available / 2)
                if readable == 0 { position = current.count; continue }
                for _ in 0..<readable {
                    scalars.append(word() ?? 0)
                }
                remaining -= readable
            } else {
                let readable = min(remaining, available)
                for _ in 0..<readable {
                    scalars.append(UInt16(byte() ?? 0))
                }
                remaining -= readable
            }
        }

        // Formatting runs and phonetic data trail the characters; skip them.
        for _ in 0..<(runCount * 4) { _ = byte() }
        for _ in 0..<farEastBytes { _ = byte() }

        var text = ""
        text.reserveCapacity(scalars.count)
        var index = 0
        while index < scalars.count {
            let unit = scalars[index]
            if unit >= 0xD800, unit <= 0xDBFF, index + 1 < scalars.count {
                let low = scalars[index + 1]
                let value = 0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(low - 0xDC00)
                if let scalar = Unicode.Scalar(value) { text.append(Character(scalar)) }
                index += 2
                continue
            }
            if let scalar = Unicode.Scalar(UInt32(unit)) { text.append(Character(scalar)) }
            index += 1
        }
        return text
    }
}
