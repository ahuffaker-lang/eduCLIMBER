import XCTest
@testable import EduClimberKit

/// The benchmark tables themselves: band matching, grade normalization, rubric
/// selection, and that the embedded Swift data matches the reference CSVs.
final class BenchmarkRubricTests: XCTestCase {

    // MARK: - Band matching

    func testAboveBelowAndExactSetBands() {
        XCTAssertTrue(BenchmarkCell.matches("O or above", level: "O"))
        XCTAssertTrue(BenchmarkCell.matches("O or above", level: "Z+"))
        XCTAssertFalse(BenchmarkCell.matches("O or above", level: "N"))

        XCTAssertTrue(BenchmarkCell.matches("K or below", level: "K"))
        XCTAssertTrue(BenchmarkCell.matches("K or below", level: "Below A"))
        XCTAssertFalse(BenchmarkCell.matches("K or below", level: "L"))

        XCTAssertTrue(BenchmarkCell.matches("G/H/I", level: "H"))
        XCTAssertFalse(BenchmarkCell.matches("G/H/I", level: "J"))
    }

    func testEarlyEmergentMeansBelowAOnly() {
        XCTAssertTrue(BenchmarkCell.matches("Early Emergent", level: "Below A"))
        XCTAssertFalse(BenchmarkCell.matches("Early Emergent", level: "A"))
    }

    func testCellPicksTheFirstMatchingBandInOrder() {
        // 4 first, then 3, 2, 1 -- exactly as the sheets print them.
        let cell = BenchmarkCell([
            BenchmarkBand(4, "P or above"), BenchmarkBand(3, "O"),
            BenchmarkBand(2, "N"), BenchmarkBand(1, "M or below"),
        ])
        XCTAssertEqual(cell.score(forLevel: "Z"), 4)
        XCTAssertEqual(cell.score(forLevel: "P"), 4)
        XCTAssertEqual(cell.score(forLevel: "O"), 3)
        XCTAssertEqual(cell.score(forLevel: "N"), 2)
        XCTAssertEqual(cell.score(forLevel: "M"), 1)
        XCTAssertEqual(cell.score(forLevel: "Below A"), 1)
        XCTAssertNil(cell.score(forLevel: "not a level"))
    }

    func testNoScaleCellHasNoBands() {
        XCTAssertFalse(BenchmarkCell.noScale.hasScale)
        XCTAssertNil(BenchmarkCell.noScale.score(forLevel: "A"))
    }

    // MARK: - Grade normalization

    func testGradeKeyRecognizesKindergartenAndOneThroughFive() {
        for text in ["K", "k", "Kinder", "Kindergarten", " K "] {
            XCTAssertEqual(BenchmarkGrade.key(forSourceGrade: text), "Kinder", text)
        }
        for n in 1...5 {
            XCTAssertEqual(BenchmarkGrade.key(forSourceGrade: "\(n)"), "Grade \(n)")
        }
    }

    func testGradeKeyRejectsSixThroughEightAndGarbage() {
        for text in ["6", "7", "8", "", "TK", "9", "K/1", "garbage"] {
            XCTAssertNil(BenchmarkGrade.key(forSourceGrade: text), text)
        }
    }

    // MARK: - Registry selection

    func testEnglishSelectsThePreTwentyTwentySixTableBeforeItsEffectiveYear() {
        let selection = try XCTUnwrap(
            BenchmarkRegistry.select(language: "English", schoolYear: "2025-2026"))
        XCTAssertEqual(selection.rubric.label, "English 2019-20")
        XCTAssertFalse(selection.isCarriedForward)
    }

    func testEnglishSelectsTheNewTableExactlyAtItsEffectiveYear() {
        let selection = try XCTUnwrap(
            BenchmarkRegistry.select(language: "English", schoolYear: "2026-2027"))
        XCTAssertEqual(selection.rubric.label, "English 2026-27")
        XCTAssertFalse(selection.isCarriedForward)
    }

    func testEnglishCarriesTheNewTableForwardPastItsEffectiveYear() {
        let selection = try XCTUnwrap(
            BenchmarkRegistry.select(language: "English", schoolYear: "2028-2029"))
        XCTAssertEqual(selection.rubric.label, "English 2026-27")
        XCTAssertTrue(selection.isCarriedForward)
        XCTAssertEqual(selection.requestedStartYear, 2028)
    }

    func testSpanishAlwaysSelectsItsOneTableNeverFlaggedAsCarriedForward() {
        for year in ["2019-2020", "2026-2027", "2031-2032"] {
            let selection = try! XCTUnwrap(
                BenchmarkRegistry.select(language: "Spanish", schoolYear: year))
            XCTAssertEqual(selection.rubric.label, "Spanish 2021-22", year)
            XCTAssertFalse(selection.isCarriedForward, year)
        }
    }

    func testSelectionIsCaseInsensitiveOnLanguage() {
        XCTAssertNotNil(BenchmarkRegistry.select(language: "english", schoolYear: "2026-2027"))
        XCTAssertNotNil(BenchmarkRegistry.select(language: "SPANISH", schoolYear: "2026-2027"))
    }

    func testUnrecognizedLanguageSelectsNothing() {
        XCTAssertNil(BenchmarkRegistry.select(language: "French", schoolYear: "2026-2027"))
    }

    // MARK: - Every shipped table tiles Below A...Z+ with no gaps or overlaps

    private static let levels = ["Below A"] + (UInt8(ascii: "A")...UInt8(ascii: "Z"))
        .map { String(UnicodeScalar($0)) } + ["Z+"]

    func testEveryRubricCellTilesCleanlyForGradesOneThroughFive() {
        for rubric in BenchmarkRegistry.rubrics {
            for grade in ["Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5"] {
                for trimester in ["T1", "T2", "T3"] {
                    guard let cell = rubric.cell(grade: grade, trimester: trimester) else {
                        XCTFail("\(rubric.label) is missing \(grade)/\(trimester)")
                        continue
                    }
                    assertTiles(cell, rubric: rubric.label, cellName: "\(grade)/\(trimester)")
                }
            }
        }
    }

    func testKindergartenHasNoScaleForTrimesterOneAndTilesOtherwise() {
        for rubric in BenchmarkRegistry.rubrics {
            let t1 = rubric.cell(grade: "Kinder", trimester: "T1")
            XCTAssertEqual(t1, .noScale, rubric.label)
            for trimester in ["T2", "T3"] {
                guard let cell = rubric.cell(grade: "Kinder", trimester: trimester) else {
                    XCTFail("\(rubric.label) is missing Kinder/\(trimester)")
                    continue
                }
                assertTiles(cell, rubric: rubric.label, cellName: "Kinder/\(trimester)")
            }
        }
    }

    private func assertTiles(_ cell: BenchmarkCell, rubric: String, cellName: String) {
        var seen: [String: Int] = [:]
        for level in Self.levels {
            guard let score = cell.score(forLevel: level) else {
                XCTFail("\(rubric) \(cellName): no band covers '\(level)'")
                continue
            }
            seen[level] = score
        }
        XCTAssertEqual(seen.count, Self.levels.count, "\(rubric) \(cellName)")
    }

    /// Grades 1-5 are covered by two of the three rubrics on 16 of 18 cells --
    /// Kindergarten is where the pre-2026 English table and the Spanish table
    /// genuinely diverge, and it would be easy to accidentally collapse them
    /// into one shared table. Pin that they stay independent.
    func testEnglishPreTwentyTwentySixAndSpanishDifferOnKindergarten() {
        let english = BenchmarkRegistry.english2019Cells["Kinder"]!
        let spanish = BenchmarkRegistry.spanish2021Cells["Kinder"]!
        XCTAssertNotEqual(english["T2"], spanish["T2"])
        XCTAssertNotEqual(english["T3"], spanish["T3"])
    }

    // MARK: - The embedded Swift data must match the reference CSVs

    func testEmbeddedRubricsMatchTheirReferenceCSVs() throws {
        try assertMatches(rubricLabel: "English 2019-20", csvName: "english_through_2025-2026.csv")
        try assertMatches(rubricLabel: "English 2026-27", csvName: "english_2026-2027_and_later.csv")
        try assertMatches(rubricLabel: "Spanish 2021-22", csvName: "spanish_current.csv")
    }

    private func assertMatches(rubricLabel: String, csvName: String) throws {
        let rubric = try XCTUnwrap(BenchmarkRegistry.rubrics.first { $0.label == rubricLabel })
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // EduClimberKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let csv = repoRoot.appendingPathComponent("Resources/Benchmarks/\(csvName)")
        let rows = CSVReader.parse(try String(contentsOf: csv, encoding: .utf8))

        for line in rows.dropFirst() where line.count >= 6 {
            let grade, trimester: String
            (grade, trimester) = (line[0], line[1])
            guard !grade.isEmpty else { continue }
            let expectedSpecs = Dictionary(uniqueKeysWithValues:
                zip([4, 3, 2, 1], [line[2], line[3], line[4], line[5]]).filter { !$0.1.isEmpty })
            let cell = rubric.cell(grade: grade, trimester: trimester)
            if expectedSpecs.isEmpty {
                XCTAssertEqual(cell, .noScale, "\(rubricLabel) \(grade)/\(trimester)")
                continue
            }
            let actualSpecs = Dictionary(
                uniqueKeysWithValues: (cell?.bands ?? []).map { ($0.score, $0.spec) })
            XCTAssertEqual(actualSpecs, expectedSpecs, "\(rubricLabel) \(grade)/\(trimester)")
        }
    }
}
