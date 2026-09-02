import XCTest
@testable import EduClimberKit

/// English and Spanish batches share a trimester and a school year, so the file
/// name is what keeps them apart.
final class FileNamingTests: XCTestCase {
    let converter = RunningRecordsConverter()

    func answers(language: String, window: String = "Trimester 2", year: String = "2026-2027")
        -> [String: String] {
        ["assessment_window": window, "school_year": year, "language": language]
    }

    func testEnglishAndSpanishGetDifferentNames() {
        let english = converter.defaultOutputName(answers: answers(language: "English"))
        let spanish = converter.defaultOutputName(answers: answers(language: "Spanish"))
        XCTAssertEqual(english, "Running_Records_English_Trimester2_2026-2027_educlimber.csv")
        XCTAssertEqual(spanish, "Running_Records_Spanish_Trimester2_2026-2027_educlimber.csv")
        XCTAssertNotEqual(english, spanish)
    }

    func testSameLanguageDifferentWindowsAlsoDiffer() {
        let first = converter.defaultOutputName(
            answers: answers(language: "Spanish", window: "Trimester 1"))
        let third = converter.defaultOutputName(
            answers: answers(language: "Spanish", window: "Trimester 3"))
        XCTAssertNotEqual(first, third)
    }

    func testCustomTemplateUsesAnyPromptAsAToken() {
        let template = FileNameTemplate("{year}_{language}_{window}_RR")
        let tokens = FileNameTemplate.tokens(
            converter: converter, answers: answers(language: "Spanish"))
        XCTAssertEqual(template.render(tokens: tokens), "2026-2027_Spanish_Trimester2_RR.csv")
    }

    func testAssessmentAndSourceAndDateTokens() {
        let tokens = FileNameTemplate.tokens(
            converter: converter,
            answers: answers(language: "English"),
            sourceName: "Fall Export.xls",
            date: Date(timeIntervalSince1970: 1_767_225_600))  // 2026-01-01 UTC
        XCTAssertEqual(
            FileNameTemplate("{assessment}").render(tokens: tokens), "RunningRecords.csv")
        XCTAssertEqual(FileNameTemplate("{source}").render(tokens: tokens), "FallExport.csv")
        XCTAssertTrue(
            FileNameTemplate("{date}").render(tokens: tokens).hasPrefix("2026-01-0"),
            FileNameTemplate("{date}").render(tokens: tokens))
    }

    func testSpacesAndIllegalCharactersAreRemoved() {
        let tokens = ["window": "Trimester 2", "year": "2026/2027", "language": "Español"]
        let name = FileNameTemplate("{language}_{window}_{year}").render(tokens: tokens)
        // Accented letters are kept -- they are perfectly good in a file name,
        // and mangling them would disfigure names like "Año" from {source}.
        XCTAssertEqual(name, "Español_Trimester2_20262027.csv")
        XCTAssertFalse(name.contains("/"), "a slash would make this a path, not a name")
        XCTAssertFalse(name.contains(" "))
    }

    func testMissingTokenDoesNotLeaveAGap() {
        let tokens = ["window": "Trimester 1", "language": ""]
        XCTAssertEqual(
            FileNameTemplate("RR_{language}_{window}_educlimber").render(tokens: tokens),
            "RR_Trimester1_educlimber.csv")
        XCTAssertEqual(FileNameTemplate("{language}_{window}").render(tokens: tokens),
                       "Trimester1.csv")
    }

    func testUnknownTokenIsIgnored() {
        let tokens = ["window": "Trimester 1"]
        XCTAssertEqual(
            FileNameTemplate("RR_{nonsense}_{window}").render(tokens: tokens), "RR_Trimester1.csv")
    }

    func testEmptyTemplateFallsBackRatherThanNamingAFileNothing() {
        XCTAssertEqual(FileNameTemplate("").render(tokens: [:]), FileNameTemplate.fallbackName)
        XCTAssertEqual(FileNameTemplate("{missing}").render(tokens: [:]),
                       FileNameTemplate.fallbackName)
    }

    func testExtensionIsNotDoubled() {
        let tokens = ["window": "Trimester 1"]
        XCTAssertEqual(FileNameTemplate("{window}.csv").render(tokens: tokens), "Trimester1.csv")
    }

    func testSuggestedURLUsesTheTemplateAndSitsBesideTheSource() {
        let source = URL(fileURLWithPath: "/tmp/exports/running.xls")
        let url = Pipeline.suggestedOutputURL(
            converter: converter,
            sourceURL: source,
            answers: answers(language: "Spanish"),
            template: "{language}_{window}")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/exports")
        XCTAssertEqual(url.lastPathComponent, "Spanish_Trimester2.csv")
    }

    func testLanguageIsRequiredLikeTheOtherPrompts() {
        var incomplete = answers(language: "")
        incomplete["language"] = ""
        let problems = Pipeline.validateAnswers(converter: converter, answers: incomplete)
        XCTAssertTrue(problems.contains { $0.contains("Language") }, "\(problems)")
    }
}
