import XCTest
@testable import EduClimberKit

/// Every converter's default export name follows the district's standard
/// convention -- `eduCLIMBER_Upload_{assessment}_{date}_{time}` -- rather
/// than a per-converter pattern. A batch that needs more than that to stay
/// unique (e.g. English vs. Spanish Running Records run the same day) can
/// still add `{language}`/`{window}`/`{year}` etc. via a custom template.
final class FileNamingTests: XCTestCase {
    let converter = RunningRecordsConverter()

    func answers(language: String, window: String = "Trimester 2", year: String = "2026-2027")
        -> [String: String] {
        ["assessment_window": window, "school_year": year, "language": language]
    }

    func testDefaultNameFollowsTheStandardConvention() {
        let name = converter.defaultOutputName(answers: answers(language: "English"))
        XCTAssertTrue(name.hasPrefix("eduCLIMBER_Upload_RunningRecords_"), name)
        XCTAssertTrue(name.hasSuffix(".csv"), name)
    }

    /// The default name no longer encodes language or window -- a batch that
    /// needs that distinction uses a custom template instead (see
    /// `testCustomTemplateUsesAnyPromptAsAToken`), so this only exercises the
    /// standard convention's own tokens.
    func testCustomTemplateCanStillDistinguishLanguageAndWindow() {
        let tokensEnglish = FileNameTemplate.tokens(
            converter: converter, answers: answers(language: "English", window: "Trimester 1"))
        let tokensSpanish = FileNameTemplate.tokens(
            converter: converter, answers: answers(language: "Spanish", window: "Trimester 3"))
        let template = FileNameTemplate("{language}_{window}_{year}_RR")
        XCTAssertNotEqual(
            template.render(tokens: tokensEnglish), template.render(tokens: tokensSpanish))
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

    /// Dashes rather than colons -- a colon is illegal in a macOS file name.
    func testTimeTokenIsHourMinuteSecondWithDashes() {
        let tokens = FileNameTemplate.tokens(
            converter: converter, answers: answers(language: "English"))
        let time = FileNameTemplate("{time}").render(tokens: tokens)
        XCTAssertNotNil(
            time.range(of: "^\\d{2}-\\d{2}-\\d{2}\\.csv$", options: .regularExpression), time)
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

    // MARK: - Language in the exported rows

    /// Spanish is a separate assessment in eduCLIMBER: same group, different
    /// name. English keeps the original name.
    func testAssessmentNameCarriesTheLanguage() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("source.csv")
        try ("Student,Student ID,Grade Level,Reading Level (A-Z),Proficiency Level\n"
             + "\"Gomez, Maria\",100234,K,Below A,At Standard\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let english = try Pipeline.convertFile(
            converter: converter, url: file, answers: answers(language: "English"))
        XCTAssertEqual(english.rows[0]["Assessment Name"], "Independent Reading Level")
        XCTAssertEqual(english.rows[0]["Assessment Group"], "Running Records")

        let spanish = try Pipeline.convertFile(
            converter: converter, url: file, answers: answers(language: "Spanish"))
        XCTAssertEqual(spanish.rows[0]["Assessment Name"], "Independent Reading Level Spanish")
        XCTAssertEqual(
            spanish.rows[0]["Assessment Group"], "Running Records",
            "the group stays the same for both languages")

        // Everything else about the row is untouched by the language.
        XCTAssertEqual(english.rows[0]["Score"], spanish.rows[0]["Score"])
        XCTAssertEqual(english.rows[0]["Student ID"], spanish.rows[0]["Student ID"])
    }

    func testAssessmentNameLookupIsForgivingOfCase() {
        XCTAssertEqual(
            RunningRecordsConverter.assessmentName(forLanguage: "spanish"),
            "Independent Reading Level Spanish")
        XCTAssertEqual(
            RunningRecordsConverter.assessmentName(forLanguage: " Spanish "),
            "Independent Reading Level Spanish")
        XCTAssertEqual(
            RunningRecordsConverter.assessmentName(forLanguage: "English"),
            "Independent Reading Level")
    }

    func testLanguageIsRequiredLikeTheOtherPrompts() {
        var incomplete = answers(language: "")
        incomplete["language"] = ""
        let problems = Pipeline.validateAnswers(converter: converter, answers: incomplete)
        XCTAssertTrue(problems.contains { $0.contains("Language") }, "\(problems)")
    }
}
