import Foundation

/// A Formative internal student id, and the WCSD email address it belongs
/// to -- resolved by hand once a Formative export arrives with a blank
/// email for that id, then remembered in a file the user manages through
/// its own window, so the same id never has to be resolved twice.
public struct FormativeIDMatch: Equatable, Hashable {
    public let formativeID: String
    public let email: String

    public init(formativeID: String, email: String) {
        self.formativeID = formativeID
        self.email = email
    }
}

/// What came of adding a batch of matches (pasted from Excel, or imported
/// from a CSV) to the existing list.
public struct FormativeIDMatchMergeResult {
    public let merged: [FormativeIDMatch]
    public let added: [FormativeIDMatch]
    /// Exact (id, email) pairs that were already present -- dropped
    /// silently when the caller doesn't ask, reported here for a summary.
    public let duplicates: [FormativeIDMatch]
    /// An incoming row whose id already maps to a *different* email. The
    /// existing entry wins; these are reported so the user can edit the
    /// existing row by hand if the new one is actually the correct one.
    public let conflicts: [FormativeIDMatch]

    public var addedCount: Int { added.count }
    public var duplicateCount: Int { duplicates.count }
}

/// A small, user-editable, persisted table: Formative id -> WCSD email.
/// Stored as a plain 2-column CSV so it's readable (and fixable) outside the
/// app too, in the same place -- Application Support -- any well-behaved Mac
/// app keeps its own data.
public enum FormativeIDMatchStore {
    public static let fileName = "formative_id_matches.csv"

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("eduCLIMBER Converter").appendingPathComponent(fileName)
    }

    static let columns: [SourceColumn] = [
        SourceColumn(key: "formative_id", label: "Formative ID",
                     aliases: ["FormativeID", "Formative Id"], example: "6aa35b06dfcecc915a66a9ba"),
        SourceColumn(key: "email", label: "Email", aliases: ["StuEmail", "Student Email"],
                     example: "student@whittiercity.net"),
    ]

    /// The persisted store's own contents, or an empty list if nothing has
    /// been saved yet -- a missing file isn't an error here, unlike an
    /// explicitly chosen import file the user expects to be read.
    public static func load(from url: URL = defaultStoreURL()) throws -> [FormativeIDMatch] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try loadMatches(fromFile: url)
    }

    /// A file the user picked to import -- any 2-column file with a
    /// Formative ID and an Email column, in either order, matched by name
    /// the same way every other file this app reads is.
    public static func loadMatches(fromFile url: URL) throws -> [FormativeIDMatch] {
        let table = try Pipeline.loadSource(at: url)
        let mapping = resolveColumns(table: table, columns: columns)
        guard !mapping.needsConfirmation, mapping.problems().isEmpty else {
            throw ConverterError(
                "This file's columns could not be matched automatically.\n"
                + mapping.unmatchedMessage())
        }
        let idHeader = mapping.match(for: "formative_id")?.header
        let emailHeader = mapping.match(for: "email")?.header
        return table.rows.compactMap { row in
            let id = table.value(row, idHeader)
            let email = table.value(row, emailHeader)
            guard !id.isEmpty, !email.isEmpty else { return nil }
            return FormativeIDMatch(formativeID: id, email: email)
        }
    }

    public static func save(_ matches: [FormativeIDMatch], to url: URL = defaultStoreURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CSVWriter.write(
            columns: ["Formative ID", "Email"],
            rows: matches.map { ["Formative ID": $0.formativeID, "Email": $0.email] },
            to: url)
    }

    /// Lines of "id<tab>email" or "id,email" -- what's on the clipboard after
    /// copying two adjacent columns in Excel, or a plain paste with no header
    /// row. A header row ("Formative ID, Email") parses to two non-empty
    /// strings too, but requiring the second to contain "@" skips it (and
    /// any other malformed line) without assuming anything about what a real
    /// Formative id looks like.
    public static func parse(pastedText: String) -> [FormativeIDMatch] {
        pastedText
            .components(separatedBy: .newlines)
            .compactMap { line -> FormativeIDMatch? in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { return nil }
                let parts = trimmedLine.contains("\t")
                    ? trimmedLine.components(separatedBy: "\t")
                    : trimmedLine.components(separatedBy: ",")
                guard parts.count >= 2 else { return nil }
                let id = parts[0].trimmingCharacters(in: .whitespaces)
                let email = parts[1].trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty, email.contains("@") else { return nil }
                return FormativeIDMatch(formativeID: id, email: email)
            }
    }

    /// Merges `incoming` into `existing`, keyed by Formative id: an exact
    /// duplicate (same id, same email) is dropped; an id that already maps
    /// to a *different* email is left out of `merged` and reported as a
    /// conflict instead of silently overwriting a trusted existing match.
    public static func merge(
        existing: [FormativeIDMatch], incoming: [FormativeIDMatch]
    ) -> FormativeIDMatchMergeResult {
        var byID: [String: FormativeIDMatch] = [:]
        for match in existing { byID[match.formativeID] = match }

        var added: [FormativeIDMatch] = []
        var duplicates: [FormativeIDMatch] = []
        var conflicts: [FormativeIDMatch] = []
        for match in incoming {
            if let current = byID[match.formativeID] {
                if current.email == match.email {
                    duplicates.append(match)
                } else {
                    conflicts.append(match)
                }
            } else {
                byID[match.formativeID] = match
                added.append(match)
            }
        }
        return FormativeIDMatchMergeResult(
            merged: existing + added, added: added, duplicates: duplicates, conflicts: conflicts)
    }
}
