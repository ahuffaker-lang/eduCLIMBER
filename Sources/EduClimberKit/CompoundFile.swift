import Foundation

/// Reads the Compound File Binary container that an Excel 97-2003 `.xls` is
/// stored in: a little filesystem of "streams", one of which holds the
/// workbook. Only reading is implemented, and only what a `.xls` needs.
struct CompoundFile {
    private let bytes: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private var fat: [UInt32] = []
    private var miniFAT: [UInt32] = []
    private var miniStream: [UInt8] = []
    private(set) var streams: [String: DirectoryEntry] = [:]

    struct DirectoryEntry {
        var name: String
        var startSector: UInt32
        var size: Int
        var isStream: Bool
    }

    static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let endOfChain: UInt32 = 0xFFFF_FFFE
    private static let freeSector: UInt32 = 0xFFFF_FFFF

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count > 512, Array(bytes[0..<8]) == Self.signature else {
            throw SourceFileError.malformedExcel("not a compound file")
        }
        sectorSize = 1 << Int(Self.uint16(bytes, 30))
        miniSectorSize = 1 << Int(Self.uint16(bytes, 32))
        miniCutoff = Int(Self.uint32(bytes, 56))
        guard sectorSize >= 128, sectorSize <= 1 << 20 else {
            throw SourceFileError.malformedExcel("unexpected sector size")
        }

        fat = try readFAT()
        miniFAT = readChainValues(
            firstSector: Self.uint32(bytes, 60), count: Int(Self.uint32(bytes, 64)))
        try readDirectory()
    }

    /// The bytes of one named stream, following its sector chain.
    func stream(named name: String) throws -> [UInt8] {
        guard let entry = streams[name] else {
            throw SourceFileError.malformedExcel("no '\(name)' stream in this workbook")
        }
        if entry.size < miniCutoff && !miniStream.isEmpty {
            return readMiniChain(from: entry.startSector, size: entry.size)
        }
        return readChain(from: entry.startSector, size: entry.size)
    }

    // MARK: - Allocation tables

    private func readFAT() throws -> [UInt32] {
        // The first 109 FAT sector numbers live in the header; the rest hang off
        // the DIFAT chain.
        var fatSectors: [UInt32] = []
        for index in 0..<109 {
            let sector = Self.uint32(bytes, 76 + index * 4)
            if sector == Self.freeSector || sector == Self.endOfChain { continue }
            fatSectors.append(sector)
        }
        var difatSector = Self.uint32(bytes, 68)
        var guardCount = 0
        while difatSector != Self.endOfChain, difatSector != Self.freeSector, guardCount < 1_000_000 {
            guardCount += 1
            guard let start = offset(of: difatSector) else { break }
            let entries = sectorSize / 4 - 1
            for index in 0..<entries {
                let sector = Self.uint32(bytes, start + index * 4)
                if sector == Self.freeSector || sector == Self.endOfChain { continue }
                fatSectors.append(sector)
            }
            difatSector = Self.uint32(bytes, start + entries * 4)
        }

        var table: [UInt32] = []
        for sector in fatSectors {
            guard let start = offset(of: sector) else { continue }
            for index in 0..<(sectorSize / 4) {
                table.append(Self.uint32(bytes, start + index * 4))
            }
        }
        guard !table.isEmpty else {
            throw SourceFileError.malformedExcel("the file allocation table is empty")
        }
        return table
    }

    private func readChainValues(firstSector: UInt32, count: Int) -> [UInt32] {
        var values: [UInt32] = []
        var sector = firstSector
        var seen = 0
        while sector != Self.endOfChain, sector != Self.freeSector, seen <= count + 1 {
            guard let start = offset(of: sector) else { break }
            for index in 0..<(sectorSize / 4) {
                values.append(Self.uint32(bytes, start + index * 4))
            }
            sector = next(after: sector)
            seen += 1
        }
        return values
    }

    private mutating func readDirectory() throws {
        let directory = readChain(from: Self.uint32(bytes, 48), size: Int.max)
        let entrySize = 128
        var index = 0
        while (index + 1) * entrySize <= directory.count {
            let base = index * entrySize
            index += 1
            let nameLength = Int(Self.uint16(directory, base + 64))
            let type = directory[base + 66]
            guard nameLength > 2, type == 2 || type == 5 else { continue }
            var scalars = ""
            for character in stride(from: 0, to: nameLength - 2, by: 2) {
                let value = Self.uint16(directory, base + character)
                if value == 0 { break }
                if let scalar = Unicode.Scalar(UInt32(value)) { scalars.append(Character(scalar)) }
            }
            let start = Self.uint32(directory, base + 116)
            let size = Int(Self.uint32(directory, base + 120))  // low 32 bits are plenty
            if type == 5 {
                // The root entry points at the mini stream that small streams live in.
                miniStream = readChain(from: start, size: size)
            } else {
                streams[scalars] = DirectoryEntry(
                    name: scalars, startSector: start, size: size, isStream: true)
            }
        }
        guard !streams.isEmpty else {
            throw SourceFileError.malformedExcel("no streams found in this workbook")
        }
    }

    // MARK: - Sector chains

    private func offset(of sector: UInt32) -> Int? {
        let start = (Int(sector) + 1) * sectorSize
        return start + sectorSize <= bytes.count ? start : nil
    }

    private func next(after sector: UInt32) -> UInt32 {
        let index = Int(sector)
        return index < fat.count ? fat[index] : Self.endOfChain
    }

    private func readChain(from firstSector: UInt32, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        var sector = firstSector
        var guardCount = 0
        while sector != Self.endOfChain, sector != Self.freeSector, guardCount < 10_000_000 {
            guardCount += 1
            guard let start = offset(of: sector) else { break }
            out.append(contentsOf: bytes[start..<(start + sectorSize)])
            if size != Int.max, out.count >= size { break }
            sector = next(after: sector)
        }
        if size != Int.max, out.count > size { out.removeLast(out.count - size) }
        return out
    }

    private func readMiniChain(from firstSector: UInt32, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        var sector = firstSector
        var guardCount = 0
        while sector != Self.endOfChain, sector != Self.freeSector, guardCount < 10_000_000 {
            guardCount += 1
            let start = Int(sector) * miniSectorSize
            guard start + miniSectorSize <= miniStream.count else { break }
            out.append(contentsOf: miniStream[start..<(start + miniSectorSize)])
            if out.count >= size { break }
            let index = Int(sector)
            sector = index < miniFAT.count ? miniFAT[index] : Self.endOfChain
        }
        if out.count > size { out.removeLast(out.count - size) }
        return out
    }

    // MARK: - Little-endian helpers

    static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        var value: UInt32 = 0
        for index in (0..<4).reversed() {
            value = value << 8 | UInt32(bytes[offset + index])
        }
        return value
    }
}
