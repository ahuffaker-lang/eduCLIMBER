import Foundation

/// One student's known facts, built up over time by fixing conversion
/// errors -- the shared cross-reference every converter falls back to when
/// its own source file is missing (or has wrong) a required field. Looked up
/// by whichever of Student ID, email, or first+last name a row does have; a
/// blank field here just means "not known yet," not "blank."
public struct StudentRosterEntry: Equatable {
    public var studentID: String
    public var email: String
    public var firstName: String
    public var lastName: String
    public var grade: String

    public init(
        studentID: String = "", email: String = "", firstName: String = "",
        lastName: String = "", grade: String = ""
    ) {
        self.studentID = studentID
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.grade = grade
    }

    public var isBlank: Bool {
        studentID.isEmpty && email.isEmpty && firstName.isEmpty && lastName.isEmpty && grade.isEmpty
    }

    /// Every converter here builds its row errors the same way -- `"Label —
    /// problem text"`, where Label is either "Last, First", "Student ID
    /// NNNN", or (Formative) a bare email -- so whichever of those a row's
    /// own label already shows can be pulled back out of the message and
    /// used to start "Fix & Remember" from what's already known, rather than
    /// blank. This matters because the field actually missing (often the
    /// Student ID itself) is usually not something a future lookup can find
    /// the fix by -- the row's name is -- so a fix that supplies only the
    /// missing field and drops what the row already had correct can never
    /// be found again on retry. A label this doesn't recognize (e.g.
    /// Formative's own opaque "Formative ID NNNN", or a combined name with
    /// no comma) yields a blank entry rather than a guess.
    public static func knownFields(fromErrorMessage message: String) -> StudentRosterEntry {
        guard let separatorRange = message.range(of: " — ") else { return StudentRosterEntry() }
        let label = String(message[message.startIndex..<separatorRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        if label.hasPrefix("Student ID ") {
            let id = label.dropFirst("Student ID ".count).trimmingCharacters(in: .whitespaces)
            return StudentRosterEntry(studentID: id)
        }
        if label.contains("@") {
            return StudentRosterEntry(email: label)
        }
        if label.contains(",") {
            let parts = label.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                return StudentRosterEntry(firstName: parts[1], lastName: parts[0])
            }
        }
        return StudentRosterEntry()
    }
}

/// A ready-to-query view of the roster, indexed by Student ID, by email, and
/// by first+last name once so every converter's lookups during one
/// conversion don't re-scan the list per row.
public struct StudentRosterLookup {
    private let byID: [String: StudentRosterEntry]
    private let byEmail: [String: StudentRosterEntry]
    private let byName: [String: StudentRosterEntry]

    public init(_ entries: [StudentRosterEntry]) {
        var byID: [String: StudentRosterEntry] = [:]
        var byEmail: [String: StudentRosterEntry] = [:]
        var byName: [String: StudentRosterEntry] = [:]
        for entry in entries {
            if !entry.studentID.isEmpty { byID[entry.studentID] = entry }
            if !entry.email.isEmpty { byEmail[entry.email.lowercased()] = entry }
            if let key = Self.nameKey(first: entry.firstName, last: entry.lastName) {
                byName[key] = entry
            }
        }
        self.byID = byID
        self.byEmail = byEmail
        self.byName = byName
    }

    public func entry(forID studentID: String) -> StudentRosterEntry? {
        studentID.isEmpty ? nil : byID[studentID]
    }

    public func entry(forEmail email: String) -> StudentRosterEntry? {
        email.isEmpty ? nil : byEmail[email.lowercased()]
    }

    /// A name alone is a much weaker key than an ID or email -- two students
    /// can share one -- so this is only ever consulted as a last resort (see
    /// `entry(studentID:email:firstName:lastName:)`), and only when both
    /// halves are given; a first name or last name alone never matches.
    public func entry(forFirstName firstName: String, lastName: String) -> StudentRosterEntry? {
        Self.nameKey(first: firstName, last: lastName).flatMap { byName[$0] }
    }

    /// Whichever of Student ID, email, or first+last name the caller has to
    /// look up by, preferring Student ID (the most stable identifier), then
    /// email, then name.
    public func entry(
        studentID: String, email: String, firstName: String = "", lastName: String = ""
    ) -> StudentRosterEntry? {
        entry(forID: studentID) ?? entry(forEmail: email)
            ?? entry(forFirstName: firstName, lastName: lastName)
    }

    /// Fills in whatever the caller's own fields are blank, from the
    /// matching roster entry. A field the caller already has always wins --
    /// the roster only fills a gap, it never overwrites a real answer. A row
    /// found only by name still gets its Student ID/email filled in from the
    /// match, the same as a row found by ID gets its name filled in.
    public func fill(
        studentID: String = "", email: String = "", firstName: String = "",
        lastName: String = "", grade: String = ""
    ) -> StudentRosterEntry {
        guard let match = entry(
            studentID: studentID, email: email, firstName: firstName, lastName: lastName)
        else {
            return StudentRosterEntry(
                studentID: studentID, email: email, firstName: firstName,
                lastName: lastName, grade: grade)
        }
        return StudentRosterEntry(
            studentID: studentID.isEmpty ? match.studentID : studentID,
            email: email.isEmpty ? match.email : email,
            firstName: firstName.isEmpty ? match.firstName : firstName,
            lastName: lastName.isEmpty ? match.lastName : lastName,
            grade: grade.isEmpty ? match.grade : grade)
    }

    /// Case- and whitespace-insensitive; `nil` unless both halves are given.
    private static func nameKey(first: String, last: String) -> String? {
        let first = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let last = last.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !first.isEmpty, !last.isEmpty else { return nil }
        return "\(last)|\(first)"
    }
}

/// What came of adding a batch of entries (pasted from Excel, imported from
/// a CSV, or a single fix from the review window) to the existing roster.
public struct StudentRosterMergeResult {
    public let merged: [StudentRosterEntry]
    public let addedCount: Int
    public let updatedCount: Int
}

/// A small, user-editable, persisted table -- Student ID / email / name /
/// grade -- stored as a plain CSV so it's readable (and fixable) outside the
/// app too, in the same place -- Application Support -- any well-behaved Mac
/// app keeps its own data. Every converter consults it as a last resort
/// before flagging a row as a problem, and the "fix it here" flow in the
/// review window writes to it directly, so a correction made once covers
/// every future file for that student, regardless of which assessment.
public enum StudentRosterStore {
    public static let fileName = "student_roster.csv"

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("eduCLIMBER Converter").appendingPathComponent(fileName)
    }

    static let columns: [SourceColumn] = [
        SourceColumn(key: "student_id", label: "Student ID", aliases: ["StudentID", "ID"],
                     isRequired: false, example: "20221371"),
        SourceColumn(key: "email", label: "Email", aliases: ["StuEmail", "Student Email"],
                     isRequired: false, example: "student@whittiercity.net"),
        SourceColumn(key: "first_name", label: "First Name", isRequired: false, example: "Agustin"),
        SourceColumn(key: "last_name", label: "Last Name", isRequired: false, example: "Hernandez Zepeda"),
        SourceColumn(key: "grade", label: "Grade", isRequired: false, example: "6"),
    ]

    /// The persisted store's own contents, or an empty list if nothing has
    /// been saved yet -- a missing file isn't an error here, unlike an
    /// explicitly chosen import file the user expects to be read.
    public static func load(from url: URL = defaultStoreURL()) throws -> [StudentRosterEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try loadEntries(fromFile: url)
    }

    /// A file the user picked to import -- any file with some subset of
    /// these five columns, in any order, matched by name the same way every
    /// other file this app reads is.
    public static func loadEntries(fromFile url: URL) throws -> [StudentRosterEntry] {
        let table = try Pipeline.loadSource(at: url)
        let mapping = resolveColumns(table: table, columns: columns)
        let idHeader = mapping.match(for: "student_id")?.header
        let emailHeader = mapping.match(for: "email")?.header
        let firstNameHeader = mapping.match(for: "first_name")?.header
        let lastNameHeader = mapping.match(for: "last_name")?.header
        let gradeHeader = mapping.match(for: "grade")?.header
        return table.rows.compactMap { row in
            let entry = StudentRosterEntry(
                studentID: table.value(row, idHeader),
                email: table.value(row, emailHeader),
                firstName: table.value(row, firstNameHeader),
                lastName: table.value(row, lastNameHeader),
                grade: table.value(row, gradeHeader))
            return entry.isBlank ? nil : entry
        }
    }

    public static func save(_ entries: [StudentRosterEntry], to url: URL = defaultStoreURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CSVWriter.write(
            columns: ["Student ID", "Email", "First Name", "Last Name", "Grade"],
            rows: entries.map {
                [
                    "Student ID": $0.studentID, "Email": $0.email,
                    "First Name": $0.firstName, "Last Name": $0.lastName, "Grade": $0.grade,
                ]
            },
            to: url)
    }

    /// Lines of "id,email,first,last,grade" (or tab-separated, what Excel
    /// puts on the clipboard) -- any column can be blank, so a student known
    /// only by name and grade is still a usable paste. A line with nothing
    /// usable at all (every field blank) is skipped rather than added as an
    /// empty row.
    public static func parse(pastedText: String) -> [StudentRosterEntry] {
        pastedText
            .components(separatedBy: .newlines)
            .compactMap { line -> StudentRosterEntry? in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.isEmpty else { return nil }
                let parts = (trimmedLine.contains("\t")
                    ? trimmedLine.components(separatedBy: "\t")
                    : trimmedLine.components(separatedBy: ","))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                func field(_ index: Int) -> String { parts.indices.contains(index) ? parts[index] : "" }
                let entry = StudentRosterEntry(
                    studentID: field(0), email: field(1), firstName: field(2),
                    lastName: field(3), grade: field(4))
                return entry.isBlank ? nil : entry
            }
    }

    /// Adds or updates entries, matched by Student ID when given, else by
    /// email. A field on the new entry replaces the existing one when it's
    /// non-blank; a blank field on the new entry never erases an existing
    /// value, so fixing a student's grade doesn't risk clobbering a name
    /// already on file for them.
    public static func upsert(
        _ incoming: [StudentRosterEntry], into entries: [StudentRosterEntry]
    ) -> StudentRosterMergeResult {
        var merged = entries
        var addedCount = 0
        var updatedCount = 0
        for entry in incoming where !entry.isBlank {
            let matchIndex = merged.firstIndex { existing in
                (!entry.studentID.isEmpty && existing.studentID == entry.studentID)
                    || (!entry.email.isEmpty && existing.email.lowercased() == entry.email.lowercased())
            }
            guard let index = matchIndex else {
                merged.append(entry)
                addedCount += 1
                continue
            }
            var existing = merged[index]
            if !entry.studentID.isEmpty { existing.studentID = entry.studentID }
            if !entry.email.isEmpty { existing.email = entry.email }
            if !entry.firstName.isEmpty { existing.firstName = entry.firstName }
            if !entry.lastName.isEmpty { existing.lastName = entry.lastName }
            if !entry.grade.isEmpty { existing.grade = entry.grade }
            merged[index] = existing
            updatedCount += 1
        }
        return StudentRosterMergeResult(merged: merged, addedCount: addedCount, updatedCount: updatedCount)
    }
}
