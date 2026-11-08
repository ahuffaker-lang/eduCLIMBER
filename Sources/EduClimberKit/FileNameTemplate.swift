import Foundation

/// A pattern for naming the exported file, e.g.
/// `eduCLIMBER_Upload_{assessment}_{date}_{time}` -- the district's standard
/// naming convention for every converter's export. Any prompt the converter
/// asks for can also be used as a token (e.g. `{language}`, `{window}`), for
/// a batch that needs more than the standard pieces to stay unique.
public struct FileNameTemplate: Equatable {
    public let pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern
    }

    public static let fallbackName = "converted.csv"

    /// Tokens available for *any* converter, beyond its own prompt keys.
    public static let generalTokens = ["assessment", "date", "time", "source"]

    /// Build the token values for one batch.
    public static func tokens(
        converter: AssessmentConverter,
        answers: [String: String],
        sourceName: String = "",
        date: Date = Date()
    ) -> [String: String] {
        var tokens: [String: String] = [:]
        for prompt in converter.prompts {
            tokens[prompt.key] = answers[prompt.key] ?? ""
        }
        // Friendlier aliases for the long prompt keys.
        tokens["window"] = tokens["window"] ?? answers["assessment_window"] ?? ""
        tokens["year"] = tokens["year"] ?? answers["school_year"] ?? ""
        tokens["assessment"] = converter.displayName

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        tokens["date"] = dateFormatter.string(from: date)

        // Dashes, not colons -- a colon is illegal in a file name on macOS
        // (Finder renders it as one, but the underlying file system rejects
        // it), and this keeps the same separator style as `date` above.
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH-mm-ss"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        tokens["time"] = timeFormatter.string(from: date)

        var base = sourceName
        if let dot = base.lastIndex(of: "."), dot != base.startIndex {
            base = String(base[base.startIndex..<dot])
        }
        tokens["source"] = base
        return tokens
    }

    /// Fill in the tokens and return a usable file name, ending in `.csv`.
    public func render(tokens: [String: String]) -> String {
        var name = ""
        var token = ""
        var insideToken = false

        for character in pattern {
            if character == "{" {
                insideToken = true
                token = ""
                continue
            }
            if character == "}", insideToken {
                insideToken = false
                let key = token.trimmingCharacters(in: .whitespaces).lowercased()
                name += Self.clean(tokens[key] ?? "")
                continue
            }
            if insideToken {
                token.append(character)
            } else {
                name.append(character)
            }
        }

        name = Self.tidySeparators(Self.clean(name, keepSeparators: true))
        if name.lowercased().hasSuffix(".csv") { name = String(name.dropLast(4)) }
        guard !name.isEmpty else { return Self.fallbackName }
        return name + ".csv"
    }

    /// Strip anything a file name should not carry. Spaces are removed rather
    /// than kept, so "Trimester 2" reads as "Trimester2" in the name.
    static func clean(_ value: String, keepSeparators: Bool = false) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        if keepSeparators { allowed.insert(charactersIn: "()[]") }
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    /// A missing token leaves a gap: "A__B_" should read "A_B".
    static func tidySeparators(_ value: String) -> String {
        var result = ""
        var lastWasSeparator = false
        for character in value {
            let isSeparator = character == "_" || character == "-"
            if isSeparator && lastWasSeparator { continue }
            if isSeparator && result.isEmpty { continue }
            result.append(character)
            lastWasSeparator = isSeparator
        }
        while let last = result.last, last == "_" || last == "-" {
            result.removeLast()
        }
        return result
    }
}
