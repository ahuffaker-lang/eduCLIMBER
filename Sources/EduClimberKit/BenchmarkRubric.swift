import Foundation

/// One score band from a district benchmark sheet, e.g. "4: O or above" or "3: L/M".
///
/// `spec` is kept exactly as the source document writes it -- "O or above", "L/M",
/// "K or below", or the literal "Early Emergent" -- so the shipped table reads like
/// the sheet it was transcribed from and can be diffed against it directly.
public struct BenchmarkBand: Equatable {
    public let score: Int
    public let spec: String

    public init(_ score: Int, _ spec: String) {
        self.score = score
        self.spec = spec
    }
}

/// The four score bands for one grade at one assessment window, in the order the
/// sheet prints them (score 4 first). An empty cell means the sheet defines no
/// 1-4 scale here at all -- every known WCSD sheet leaves Kindergarten blank for
/// Trimester 1.
public struct BenchmarkCell: Equatable {
    public let bands: [BenchmarkBand]

    public init(_ bands: [BenchmarkBand]) {
        self.bands = bands
    }

    public static let noScale = BenchmarkCell([])

    public var hasScale: Bool { !bands.isEmpty }

    /// The 1-4 score for a reading level already validated against `ReadingLevels`,
    /// or nil if the level does not fall in this cell (should not happen once every
    /// band tiles Below A...Z+ with no gaps, which the test suite checks for every
    /// shipped rubric).
    public func score(forLevel level: String) -> Int? {
        for band in bands {
            if BenchmarkCell.matches(band.spec, level: level) { return band.score }
        }
        return nil
    }

    /// Whether `spec` (as printed on the sheet) covers `level`.
    ///
    /// `ReadingLevels.score(for:)` returns each level's position in the Below A...Z+
    /// sequence (Below A = 1, A = 2, ... Z+ = 28, MAX = 29); reused here purely as an
    /// ordering rank for the "or above" / "or below" comparisons, not as the letter
    /// score it normally means elsewhere in the app.
    static func matches(_ spec: String, level: String) -> Bool {
        guard let levelRank = ReadingLevels.score(for: level) else { return false }
        let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("Early Emergent") == .orderedSame {
            return levelRank == ReadingLevels.score(for: "Below A")
        }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("or above") {
            let base = String(trimmed.dropLast("or above".count)).trimmingCharacters(in: .whitespaces)
            guard let baseRank = ReadingLevels.score(for: base) else { return false }
            return levelRank >= baseRank
        }
        if lower.hasSuffix("or below") {
            let base = String(trimmed.dropLast("or below".count)).trimmingCharacters(in: .whitespaces)
            guard let baseRank = ReadingLevels.score(for: base) else { return false }
            return levelRank <= baseRank
        }
        // An exact set, e.g. "G/H/I".
        for option in trimmed.split(separator: "/") {
            let name = option.trimmingCharacters(in: .whitespaces)
            if let optionRank = ReadingLevels.score(for: name), optionRank == levelRank { return true }
        }
        return false
    }
}

/// One district benchmark table: a language, the school year it takes effect, and
/// its K-5 grid of cells. Grades 6-8 are intentionally not stored -- the district
/// does not use the benchmark for those grades, and a lookup miss is exactly the
/// signal the converter needs to flag those rows rather than score them.
public struct BenchmarkRubric {
    public let language: String
    /// Shown in the app's Benchmark line, e.g. "English 2026-27".
    public let label: String
    /// The first school year (as its starting year, e.g. 2026 for "2026-2027") this
    /// rubric applies to. `nil` means it applies to any year not claimed by a more
    /// specific, later-dated rubric for the same language -- how the pre-2026-27
    /// English table and the Spanish table (in force "until another build") are
    /// both represented.
    public let effectiveFromYear: Int?
    public let cells: [String: [String: BenchmarkCell]]

    public init(
        language: String, label: String, effectiveFromYear: Int?,
        cells: [String: [String: BenchmarkCell]]
    ) {
        self.language = language
        self.label = label
        self.effectiveFromYear = effectiveFromYear
        self.cells = cells
    }

    public func cell(grade: String, trimester: String) -> BenchmarkCell? {
        cells[grade]?[trimester]
    }
}

/// The rubric's grade key for a source `Grade Level` value, or nil when the
/// benchmark does not cover this grade -- grades 6-8 and anything unrecognized.
public enum BenchmarkGrade {
    public static func key(forSourceGrade raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "K" || trimmed == "KINDER" || trimmed == "KINDERGARTEN" { return "Kinder" }
        if let number = Int(trimmed), (1...5).contains(number) { return "Grade \(number)" }
        return nil
    }
}
