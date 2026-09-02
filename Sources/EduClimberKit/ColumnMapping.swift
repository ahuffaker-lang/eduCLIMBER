import Foundation

/// Shown in the picker for a column that isn't in the file at all.
public let notInFileLabel = "— not in this file —"

/// Below this similarity a header isn't worth suggesting.
let suggestionFloor = 0.45

/// What we think holds one expected column, and how sure we are.
public struct ColumnMatch {
    public let column: SourceColumn
    public var header: String?
    /// Matched on header text alone -- no question needed.
    public var isAutomatic: Bool = false
    /// The user picked this one.
    public var isConfirmed: Bool = false
    /// Headers in the file, most likely first.
    public var suggestions: [String] = []

    /// True when this column needs no question asked of the user.
    public var isSettled: Bool {
        if isConfirmed { return true }
        if isAutomatic, header != nil { return true }
        // An optional column with nothing resembling it needs no question.
        return !column.isRequired && suggestions.isEmpty
    }

    public var bestGuess: String? { header ?? suggestions.first }

    public var describe: String {
        if let header { return "'\(column.label)' → '\(header)'" }
        return "'\(column.label)' → (not found)"
    }
}

/// Expected columns lined up against the headers in one file.
public struct ColumnMapping {
    public var matches: [ColumnMatch]
    public let headers: [String]

    public init(matches: [ColumnMatch], headers: [String]) {
        self.matches = matches
        self.headers = headers
    }

    public func match(for key: String) -> ColumnMatch? {
        matches.first { $0.column.key == key }
    }

    /// Columns the user still has to confirm or point somewhere.
    public var unsettled: [ColumnMatch] { matches.filter { !$0.isSettled } }

    public var needsConfirmation: Bool { !unsettled.isEmpty }

    public var asDictionary: [String: String?] {
        var result: [String: String?] = [:]
        for match in matches { result[match.column.key] = match.header }
        return result
    }

    /// Record the user's picks. A nil header means "not in this file".
    public mutating func apply(_ choices: [String: String?]) {
        for (key, header) in choices {
            guard let index = matches.firstIndex(where: { $0.column.key == key }) else { continue }
            matches[index].header = (header?.isEmpty ?? true) ? nil : header
            matches[index].isConfirmed = true
        }
    }

    /// Reasons this mapping can't be used yet.
    public func problems() -> [String] {
        var issues: [String] = []
        for match in matches where match.column.isRequired && match.header == nil {
            issues.append("No column chosen for '\(match.column.label)'.")
        }
        var usedBy: [String: [String]] = [:]
        for match in matches {
            guard let header = match.header else { continue }
            usedBy[header, default: []].append(match.column.label)
        }
        for header in headers {
            guard let labels = usedBy[header], labels.count > 1 else { continue }
            issues.append(
                "'\(header)' is assigned to more than one expected column: "
                + labels.joined(separator: ", ") + ".")
        }
        return issues
    }

    /// Plain-language description of what could not be matched.
    public func unmatchedMessage() -> String {
        var lines = ["These expected columns did not match any header in the file:"]
        for match in unsettled {
            let hint = match.suggestions.first.map { " — closest header in the file: '\($0)'" } ?? ""
            lines.append("  \(match.column.label)\(hint)")
        }
        let found = headers.isEmpty ? "(none)" : headers.joined(separator: ", ")
        lines.append("Columns found in this file: \(found)")
        return lines.joined(separator: "\n")
    }
}

/// Auto-match what we can; rank suggestions for the rest.
public func resolveColumns(table: Table, columns: [SourceColumn]) -> ColumnMapping {
    var matches: [ColumnMatch] = []
    var taken: Set<String> = []

    for column in columns {
        var header = table.findColumn(column.matchNames)
        if let found = header, taken.contains(found) { header = nil }
        if let found = header {
            taken.insert(found)
            matches.append(ColumnMatch(column: column, header: found, isAutomatic: true))
        } else {
            matches.append(ColumnMatch(column: column, header: nil))
        }
    }

    // Rank suggestions only over headers no column claimed, so "Student ID" is
    // not offered as the likeliest match for a misspelled "Student".
    let available = table.headers.filter { !taken.contains($0) }
    for index in matches.indices where matches[index].header == nil {
        matches[index].suggestions = rankHeaders(for: matches[index].column, headers: available)
    }
    return ColumnMapping(matches: matches, headers: table.headers)
}

/// The file's headers, most likely first, for one expected column.
///
/// Written as a loop rather than a map/filter/sort chain: the chained version is
/// more than the Swift type-checker will solve in reasonable time.
public func rankHeaders(for column: SourceColumn, headers: [String]) -> [String] {
    var scored: [(header: String, score: Double)] = []
    for header in headers {
        let score = similarity(column: column, header: header)
        if score >= suggestionFloor {
            scored.append((header: header, score: score))
        }
    }
    scored.sort { left, right in
        if left.score == right.score { return left.header < right.header }
        return left.score > right.score
    }
    return scored.map { $0.header }
}

/// How much `header` looks like any of the names `column` answers to.
public func similarity(column: SourceColumn, header: String) -> Double {
    let target = normalizeHeader(header)
    guard !target.isEmpty else { return 0 }
    var best = 0.0
    for name in column.matchNames {
        let candidate = normalizeHeader(name)
        guard !candidate.isEmpty else { continue }
        var score = editDistanceRatio(candidate, target)
        if candidate.contains(target) || target.contains(candidate) {
            score = max(score, 0.85)
        }
        best = max(best, score)
    }
    return best
}

/// 1 - (edit distance / length of the longer string).
func editDistanceRatio(_ left: String, _ right: String) -> Double {
    if left == right { return 1 }
    let longest = max(left.count, right.count)
    guard longest > 0 else { return 1 }
    return 1 - Double(editDistance(left, right)) / Double(longest)
}

func editDistance(_ left: String, _ right: String) -> Int {
    let source = Array(left)
    let target = Array(right)
    if source.isEmpty { return target.count }
    if target.isEmpty { return source.count }

    var previous = Array(0...target.count)
    var current = [Int](repeating: 0, count: target.count + 1)
    for sourceIndex in 1...source.count {
        current[0] = sourceIndex
        for targetIndex in 1...target.count {
            let cost = source[sourceIndex - 1] == target[targetIndex - 1] ? 0 : 1
            current[targetIndex] = min(
                current[targetIndex - 1] + 1,      // insert
                previous[targetIndex] + 1,          // delete
                previous[targetIndex - 1] + cost)   // substitute
        }
        swap(&previous, &current)
    }
    return previous[target.count]
}
