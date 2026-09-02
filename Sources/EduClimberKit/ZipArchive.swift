import Foundation
#if canImport(Compression)
import Compression
#endif

/// Just enough ZIP to read the XML parts of an .xlsx file.
///
/// An .xlsx is a ZIP of XML documents. Reading it directly with Apple's
/// Compression framework keeps the app dependency-free -- nothing to fetch,
/// vendor, or keep up to date for an Xcode build.
struct ZipArchive {
    private let data: Data
    private(set) var entries: [String: Entry] = [:]

    struct Entry {
        var name: String
        var compressionMethod: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    init(contentsOf url: URL) throws {
        do {
            try self.init(data: try Data(contentsOf: url))
        } catch let error as SourceFileError {
            throw error
        } catch {
            throw SourceFileError.unreadable(error.localizedDescription)
        }
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// The decompressed bytes of one archive member.
    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw SourceFileError.malformedExcel("missing part \(name)")
        }
        // The local file header repeats the name and adds a variable extra field,
        // so the payload offset has to be computed from it rather than assumed.
        let headerStart = entry.localHeaderOffset
        guard headerStart + 30 <= data.count,
              readUInt32(at: headerStart) == 0x0403_4b50 else {
            throw SourceFileError.malformedExcel("bad local header for \(name)")
        }
        let nameLength = Int(readUInt16(at: headerStart + 26))
        let extraLength = Int(readUInt16(at: headerStart + 28))
        let start = headerStart + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard end <= data.count else {
            throw SourceFileError.malformedExcel("truncated data for \(name)")
        }
        let payload = data.subdata(in: start..<end)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try inflate(payload, expectedSize: entry.uncompressedSize, name: name)
        default:
            throw SourceFileError.malformedExcel(
                "unsupported compression method \(entry.compressionMethod)")
        }
    }

    private func inflate(_ payload: Data, expectedSize: Int, name: String) throws -> Data {
        #if canImport(Compression)
        // ZIP method 8 is raw deflate, which is COMPRESSION_ZLIB in Apple's API.
        let capacity = max(expectedSize, payload.count * 4, 4096)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            payload.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else {
            throw SourceFileError.malformedExcel("could not decompress \(name)")
        }
        return output.prefix(written)
        #else
        throw SourceFileError.malformedExcel("decompression is unavailable on this platform")
        #endif
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        guard data.count > 22 else { throw SourceFileError.malformedExcel("file is too small") }
        guard let eocd = findEndOfCentralDirectory(data) else {
            throw SourceFileError.malformedExcel("not a ZIP archive")
        }
        let count = Int(read16(data, eocd + 10))
        var offset = Int(read32(data, eocd + 16))

        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= data.count, read32(data, offset) == 0x0201_4b50 else {
                throw SourceFileError.malformedExcel("bad central directory entry")
            }
            let method = read16(data, offset + 10)
            let compressedSize = Int(read32(data, offset + 20))
            let uncompressedSize = Int(read32(data, offset + 24))
            let nameLength = Int(read16(data, offset + 28))
            let extraLength = Int(read16(data, offset + 30))
            let commentLength = Int(read16(data, offset + 32))
            let localOffset = Int(read32(data, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else {
                throw SourceFileError.malformedExcel("truncated central directory")
            }
            let name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8) ?? ""
            entries[name] = Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset)
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The end-of-central-directory record sits in the last 64KB, after the
    /// (variable length) archive comment.
    private static func findEndOfCentralDirectory(_ data: Data) -> Int? {
        let minimum = max(0, data.count - 65_557)
        var index = data.count - 22
        while index >= minimum {
            if read32(data, index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    private func readUInt16(at offset: Int) -> UInt16 { Self.read16(data, offset) }
    private func readUInt32(at offset: Int) -> UInt32 { Self.read32(data, offset) }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count, offset >= 0 else { return 0 }
        return UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count, offset >= 0 else { return 0 }
        var value: UInt32 = 0
        for byte in (0..<4).reversed() {
            value = value << 8 | UInt32(data[data.startIndex + offset + byte])
        }
        return value
    }
}
