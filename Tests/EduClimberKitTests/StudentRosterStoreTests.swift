import XCTest
@testable import EduClimberKit

final class StudentRosterStoreTests: XCTestCase {
    func tempURL(_ name: String = "student_roster.csv") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    // MARK: - Load / save round-trip

    func testMissingFileReturnsEmptyList() throws {
        XCTAssertEqual(try StudentRosterStore.load(from: tempURL()), [])
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempURL()
        let entries = [
            StudentRosterEntry(
                studentID: "20221371", email: "agustinh6aa35b06dfcecc915a66a9ba@example.com",
                firstName: "Agustin", lastName: "Hernandez Zepeda", grade: "6"),
            StudentRosterEntry(studentID: "20222971", firstName: "Maximiliano"),
        ]
        try StudentRosterStore.save(entries, to: url)
        XCTAssertEqual(try StudentRosterStore.load(from: url), entries)
    }

    func testSaveCreatesTheParentDirectory() throws {
        let url = tempURL()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        try StudentRosterStore.save([StudentRosterEntry(studentID: "1")], to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Importing a file

    func testLoadEntriesFromFileAcceptsAnyColumnSubsetAndOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("import.csv")
        try "Grade,Student ID\n6,20221371\nK,20220530\n".write(
            to: file, atomically: true, encoding: .utf8)
        let entries = try StudentRosterStore.loadEntries(fromFile: file)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.studentID, "20221371")
        XCTAssertEqual(entries.first?.grade, "6")
        XCTAssertEqual(entries.first?.email, "")
    }

    func testLoadEntriesFromFileSkipsFullyBlankRows() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("import.csv")
        try "Student ID,Email,First Name,Last Name,Grade\n20221371,,,,6\n,,,,\n".write(
            to: file, atomically: true, encoding: .utf8)
        let entries = try StudentRosterStore.loadEntries(fromFile: file)
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - Parsing pasted text

    func testParsePastedTextAcceptsTabOrCommaSeparated() {
        let tab = StudentRosterStore.parse(
            pastedText: "20221371\tagustin@example.com\tAgustin\tHernandez Zepeda\t6")
        XCTAssertEqual(tab.count, 1)
        XCTAssertEqual(tab.first?.studentID, "20221371")
        XCTAssertEqual(tab.first?.grade, "6")

        let comma = StudentRosterStore.parse(
            pastedText: "20221371,agustin@example.com,Agustin,Hernandez Zepeda,6")
        XCTAssertEqual(comma, tab)
    }

    func testParsePastedTextAllowsAnyFieldBlank() {
        let entries = StudentRosterStore.parse(pastedText: "20222971,,Maximiliano")
        XCTAssertEqual(entries, [StudentRosterEntry(studentID: "20222971", firstName: "Maximiliano")])
    }

    func testParsePastedTextSkipsBlankLinesAndFullyBlankRows() {
        let entries = StudentRosterStore.parse(pastedText: "\n20221371\n,,,,\n\n")
        XCTAssertEqual(entries, [StudentRosterEntry(studentID: "20221371")])
    }

    // MARK: - Merging

    func testUpsertAddsANewEntry() {
        let result = StudentRosterStore.upsert([StudentRosterEntry(studentID: "1", firstName: "A")], into: [])
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.merged, [StudentRosterEntry(studentID: "1", firstName: "A")])
    }

    func testUpsertUpdatesAnExistingEntryMatchedByStudentID() {
        let existing = [StudentRosterEntry(studentID: "1", firstName: "A")]
        let result = StudentRosterStore.upsert(
            [StudentRosterEntry(studentID: "1", grade: "6")], into: existing)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.merged, [StudentRosterEntry(studentID: "1", firstName: "A", grade: "6")])
    }

    func testUpsertMatchesByEmailWhenStudentIDIsBlank() {
        let existing = [StudentRosterEntry(email: "a@example.com", firstName: "A")]
        let result = StudentRosterStore.upsert(
            [StudentRosterEntry(email: "a@example.com", grade: "6")], into: existing)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(
            result.merged, [StudentRosterEntry(email: "a@example.com", firstName: "A", grade: "6")])
    }

    /// A blank field on the incoming entry never erases a value the
    /// existing entry already has -- only a non-blank field overwrites.
    func testUpsertNeverErasesAnExistingFieldWithBlank() {
        let existing = [StudentRosterEntry(studentID: "1", firstName: "A", lastName: "B", grade: "6")]
        let result = StudentRosterStore.upsert([StudentRosterEntry(studentID: "1", grade: "7")], into: existing)
        XCTAssertEqual(
            result.merged, [StudentRosterEntry(studentID: "1", firstName: "A", lastName: "B", grade: "7")])
    }

    func testUpsertIgnoresABlankIncomingEntry() {
        let existing = [StudentRosterEntry(studentID: "1", firstName: "A")]
        let result = StudentRosterStore.upsert([StudentRosterEntry()], into: existing)
        XCTAssertEqual(result.merged, existing)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.updatedCount, 0)
    }

    // MARK: - Lookup / fill

    func testLookupPrefersStudentIDOverEmail() {
        let lookup = StudentRosterLookup([
            StudentRosterEntry(studentID: "1", email: "a@example.com", firstName: "ByID"),
        ])
        XCTAssertEqual(lookup.entry(studentID: "1", email: "a@example.com")?.firstName, "ByID")
        XCTAssertEqual(lookup.entry(forEmail: "A@EXAMPLE.COM")?.firstName, "ByID", "email lookup is case-insensitive")
    }

    func testFillOnlyFillsBlankFields() {
        let lookup = StudentRosterLookup([
            StudentRosterEntry(studentID: "1", firstName: "Roster", lastName: "Name", grade: "6"),
        ])
        let filled = lookup.fill(studentID: "1", firstName: "", lastName: "Keep This", grade: "")
        XCTAssertEqual(filled.firstName, "Roster", "blank field filled from the roster")
        XCTAssertEqual(filled.lastName, "Keep This", "a real value is never overwritten")
        XCTAssertEqual(filled.grade, "6")
    }

    func testFillLeavesEverythingUnchangedWhenNothingMatches() {
        let lookup = StudentRosterLookup([])
        let filled = lookup.fill(studentID: "1", firstName: "", lastName: "", grade: "")
        XCTAssertEqual(filled.studentID, "1")
        XCTAssertTrue(filled.firstName.isEmpty)
    }

    // MARK: - Name is a fallback key, for when the row's own missing field
    // is the very field (Student ID) a lookup would otherwise use

    /// The exact bug this covers: a row missing its Student ID can't be
    /// looked up by ID (it doesn't have one), so a fix saved under that ID
    /// has to be found again by the name the row already has.
    func testFillFindsAMatchByNameWhenStudentIDAndEmailAreBothBlank() {
        let lookup = StudentRosterLookup([
            StudentRosterEntry(studentID: "20212318", firstName: "Ethan", lastName: "Garcia"),
        ])
        let filled = lookup.fill(studentID: "", firstName: "Ethan", lastName: "Garcia")
        XCTAssertEqual(filled.studentID, "20212318")
    }

    func testNameLookupIsCaseAndWhitespaceInsensitive() {
        let lookup = StudentRosterLookup([
            StudentRosterEntry(studentID: "1", firstName: "Ethan", lastName: "Garcia"),
        ])
        XCTAssertEqual(lookup.entry(forFirstName: " ethan ", lastName: " GARCIA ")?.studentID, "1")
    }

    /// A first or last name alone is too weak to key off of -- only a
    /// matching pair counts.
    func testNameLookupRequiresBothHalves() {
        let lookup = StudentRosterLookup([
            StudentRosterEntry(studentID: "1", firstName: "Ethan", lastName: "Garcia"),
        ])
        XCTAssertNil(lookup.entry(forFirstName: "Ethan", lastName: ""))
        XCTAssertNil(lookup.entry(forFirstName: "", lastName: "Garcia"))
    }

    /// Student ID and email still win over a name match when either is
    /// available -- name is the weakest key, used only as a last resort.
    func testIDAndEmailAreStillPreferredOverName() {
        let lookup = StudentRosterLookup([
            StudentRosterEntry(studentID: "1", firstName: "Ethan", lastName: "Garcia", grade: "byID"),
        ])
        let filled = lookup.fill(studentID: "1", firstName: "Ethan", lastName: "Garcia")
        XCTAssertEqual(filled.grade, "byID")
    }

    /// A roster entry saved with only a Student ID (no name) was never
    /// indexed by name in the first place, so it can't be found by name --
    /// this documents why Fix & Remember pre-fills the name from the row's
    /// own error message instead of leaving the sheet blank.
    func testAnEntryWithNoNameIsNotFoundByName() {
        let lookup = StudentRosterLookup([StudentRosterEntry(studentID: "20212318")])
        XCTAssertNil(lookup.entry(forFirstName: "Ethan", lastName: "Garcia"))
    }

    // MARK: - Recovering known fields from a converter's own error message

    func testKnownFieldsParsesALastFirstLabel() {
        let entry = StudentRosterEntry.knownFields(
            fromErrorMessage: "Garcia, Ethan — Student ID is blank.")
        XCTAssertEqual(entry, StudentRosterEntry(firstName: "Ethan", lastName: "Garcia"))
    }

    func testKnownFieldsParsesAStudentIDLabel() {
        let entry = StudentRosterEntry.knownFields(
            fromErrorMessage: "Student ID 20212318 — Student Name is blank.")
        XCTAssertEqual(entry, StudentRosterEntry(studentID: "20212318"))
    }

    func testKnownFieldsParsesABareEmailLabel() {
        let entry = StudentRosterEntry.knownFields(
            fromErrorMessage: "egarcia18@whittiercity.net — has no email in the export.")
        XCTAssertEqual(entry, StudentRosterEntry(email: "egarcia18@whittiercity.net"))
    }

    /// Formative's own opaque internal ID is not a Student ID -- prefilling
    /// it into the Student ID field would be actively wrong, not just
    /// unhelpful.
    func testKnownFieldsIgnoresAFormativeIDLabel() {
        let entry = StudentRosterEntry.knownFields(
            fromErrorMessage: "Formative ID 3d1955fc — has no email in the export.")
        XCTAssertTrue(entry.isBlank)
    }

    func testKnownFieldsReturnsBlankWhenThereIsNoLabelAtAll() {
        XCTAssertTrue(StudentRosterEntry.knownFields(fromErrorMessage: "Grade is blank.").isBlank)
    }
}
