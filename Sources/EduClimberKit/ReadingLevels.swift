import Foundation

/// The Reading Level -> Score lookup (also kept alongside the app as
/// `Data_Table.csv`; a unit test checks the two stay identical).
public enum ReadingLevels {
    public static let ordered: [(level: String, score: Int)] = [
        ("Below A", 1), ("A", 2), ("B", 3), ("C", 4), ("D", 5), ("E", 6), ("F", 7),
        ("G", 8), ("H", 9), ("I", 10), ("J", 11), ("K", 12), ("L", 13), ("M", 14),
        ("N", 15), ("O", 16), ("P", 17), ("Q", 18), ("R", 19), ("S", 20), ("T", 21),
        ("U", 22), ("V", 23), ("W", 24), ("X", 25), ("Y", 26), ("Z", 27), ("Z+", 28),
        ("MAX", 29),
    ]

    static let byKey: [String: Int] = {
        var table: [String: Int] = [:]
        for entry in ordered { table[key(entry.level)] = entry.score }
        return table
    }()

    /// Case and inner spacing don't matter: "below a" finds "Below A".
    static func key(_ level: String) -> String {
        let collapsed = level
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.uppercased()
    }

    /// The numeric score for a reading level, or nil when it isn't in the table.
    public static func score(for level: String) -> Int? {
        byKey[key(level)]
    }
}
