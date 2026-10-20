import XCTest
@testable import EduClimberKit

final class FormativeIDMatchStoreTests: XCTestCase {
    func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("formative_id_matches.csv")
    }

    // MARK: - Save / load round trip

    func testSaveAndLoadRoundTrip() throws {
        let url = tempFile()
        let matches = [
            FormativeIDMatch(formativeID: "6aa35b06dfcecc915a66a9ba", email: "a@whittiercity.net"),
            FormativeIDMatch(formativeID: "671be2e82c230fc28ce666f6", email: "b@whittiercity.net"),
        ]
        try FormativeIDMatchStore.save(matches, to: url)
        XCTAssertEqual(try FormativeIDMatchStore.load(from: url), matches)
    }

    func testLoadingAMissingFileReturnsAnEmptyListNotAnError() throws {
        let url = tempFile()
        XCTAssertEqual(try FormativeIDMatchStore.load(from: url), [])
    }

    func testSaveCreatesIntermediateDirectories() throws {
        let url = tempFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        try FormativeIDMatchStore.save([FormativeIDMatch(formativeID: "x", email: "y@z.net")], to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Importing an arbitrary file

    func testLoadMatchesFromFileAcceptsEitherColumnOrder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("import.csv")
        try "Email,Formative ID\na@whittiercity.net,abc123\n".write(to: file, atomically: true, encoding: .utf8)
        let matches = try FormativeIDMatchStore.loadMatches(fromFile: file)
        XCTAssertEqual(matches, [FormativeIDMatch(formativeID: "abc123", email: "a@whittiercity.net")])
    }

    func testThrowsWhenAnImportFileCannotBeRead() {
        XCTAssertThrowsError(try FormativeIDMatchStore.loadMatches(fromFile: tempFile()))
    }

    // MARK: - Parsing pasted text

    func testParsesTabSeparatedPastedRows() {
        let matches = FormativeIDMatchStore.parse(pastedText: "abc123\ta@whittiercity.net\nxyz789\tb@whittiercity.net")
        XCTAssertEqual(matches, [
            FormativeIDMatch(formativeID: "abc123", email: "a@whittiercity.net"),
            FormativeIDMatch(formativeID: "xyz789", email: "b@whittiercity.net"),
        ])
    }

    func testParsesCommaSeparatedPastedRows() {
        let matches = FormativeIDMatchStore.parse(pastedText: "abc123,a@whittiercity.net")
        XCTAssertEqual(matches, [FormativeIDMatch(formativeID: "abc123", email: "a@whittiercity.net")])
    }

    func testSkipsAHeaderRowByRequiringAnAtSignInTheEmailPart() {
        let matches = FormativeIDMatchStore.parse(pastedText: "Formative ID\tEmail\nabc123\ta@whittiercity.net")
        XCTAssertEqual(matches, [FormativeIDMatch(formativeID: "abc123", email: "a@whittiercity.net")])
    }

    func testSkipsBlankLines() {
        let matches = FormativeIDMatchStore.parse(pastedText: "abc123\ta@whittiercity.net\n\n   \n")
        XCTAssertEqual(matches.count, 1)
    }

    func testSkipsALineWithOnlyOneColumn() {
        let matches = FormativeIDMatchStore.parse(pastedText: "abc123\nxyz789\tb@whittiercity.net")
        XCTAssertEqual(matches, [FormativeIDMatch(formativeID: "xyz789", email: "b@whittiercity.net")])
    }

    // MARK: - Merging

    func testMergeAddsNewMatches() {
        let result = FormativeIDMatchStore.merge(
            existing: [FormativeIDMatch(formativeID: "a", email: "a@z.net")],
            incoming: [FormativeIDMatch(formativeID: "b", email: "b@z.net")])
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.duplicateCount, 0)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.merged.count, 2)
    }

    func testMergeDropsExactDuplicatesSilently() {
        let existing = [FormativeIDMatch(formativeID: "a", email: "a@z.net")]
        let result = FormativeIDMatchStore.merge(existing: existing, incoming: existing)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(result.merged, existing)
    }

    func testMergeReportsAConflictAndKeepsTheExistingEmail() {
        let existing = [FormativeIDMatch(formativeID: "a", email: "old@z.net")]
        let incoming = [FormativeIDMatch(formativeID: "a", email: "new@z.net")]
        let result = FormativeIDMatchStore.merge(existing: existing, incoming: incoming)
        XCTAssertEqual(result.conflicts, incoming)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.merged, existing, "the existing mapping should win, not be overwritten")
    }

    func testMergeDedupesWithinTheIncomingBatchItself() {
        let incoming = [
            FormativeIDMatch(formativeID: "a", email: "a@z.net"),
            FormativeIDMatch(formativeID: "a", email: "a@z.net"),
        ]
        let result = FormativeIDMatchStore.merge(existing: [], incoming: incoming)
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.duplicateCount, 1)
    }
}
