import XCTest
@testable import EduClimberKit

final class PipelineDuplicateResolutionTests: XCTestCase {
    func makeTable(_ ids: [String]) -> Table {
        Table(headers: ["ID"], rows: ids.map { ["ID": $0] })
    }

    func testKeepsTheChosenRowFromEachGroup() {
        let table = makeTable(["a", "b1", "b2", "c"])
        let result = Pipeline.resolvingDuplicates(in: table, groups: [[1, 2]], selections: [1])
        XCTAssertEqual(result.rows.map { $0["ID"] }, ["a", "b2", "c"])
    }

    func testPicksTheFirstCandidateWhenSelectionIsZero() {
        let table = makeTable(["a", "b1", "b2", "c"])
        let result = Pipeline.resolvingDuplicates(in: table, groups: [[1, 2]], selections: [0])
        XCTAssertEqual(result.rows.map { $0["ID"] }, ["a", "b1", "c"])
    }

    func testHandlesMultipleIndependentGroups() {
        let table = makeTable(["a1", "a2", "b", "c1", "c2", "c3"])
        let result = Pipeline.resolvingDuplicates(
            in: table, groups: [[0, 1], [3, 4, 5]], selections: [1, 2])
        XCTAssertEqual(result.rows.map { $0["ID"] }, ["a2", "b", "c3"])
    }

    func testRowsOutsideAnyGroupPassThroughUnchanged() {
        let table = makeTable(["a", "b", "c"])
        let result = Pipeline.resolvingDuplicates(in: table, groups: [], selections: [])
        XCTAssertEqual(result.rows.map { $0["ID"] }, ["a", "b", "c"])
    }

    func testRowNumbersFollowTheKeptRows() {
        let table = Table(headers: ["ID"], rows: [["ID": "a"], ["ID": "b1"], ["ID": "b2"]])
        let result = Pipeline.resolvingDuplicates(in: table, groups: [[1, 2]], selections: [1])
        XCTAssertEqual(result.rowNumber(0), table.rowNumber(0))
        XCTAssertEqual(result.rowNumber(1), table.rowNumber(2))
    }

    func testMismatchedGroupsAndSelectionsCountReturnsTableUnchanged() {
        let table = makeTable(["a", "b1", "b2"])
        let result = Pipeline.resolvingDuplicates(in: table, groups: [[1, 2]], selections: [])
        XCTAssertEqual(result.rows.map { $0["ID"] }, ["a", "b1", "b2"])
    }
}
