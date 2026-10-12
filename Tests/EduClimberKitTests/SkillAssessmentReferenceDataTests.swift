import XCTest
@testable import EduClimberKit

final class SkillAssessmentReferenceDataTests: XCTestCase {
    func testAeriesGradeCodes() {
        XCTAssertEqual(SkillAssessmentReferenceData.eduClimberGrade(forAeriesCode: -1), "TK")
        XCTAssertEqual(SkillAssessmentReferenceData.eduClimberGrade(forAeriesCode: 0), "K")
        XCTAssertEqual(SkillAssessmentReferenceData.eduClimberGrade(forAeriesCode: 1), "1")
        XCTAssertEqual(SkillAssessmentReferenceData.eduClimberGrade(forAeriesCode: 12), "12")
    }

    func testUnrecognizedGradeCodeIsNil() {
        XCTAssertNil(SkillAssessmentReferenceData.eduClimberGrade(forAeriesCode: -2))
    }

    func testSchoolNamesTableHasAllTwelveDistrictSchools() {
        XCTAssertEqual(SkillAssessmentReferenceData.schoolNames.count, 12)
        XCTAssertEqual(SkillAssessmentReferenceData.schoolNames[667], "Longfellow")
        XCTAssertEqual(SkillAssessmentReferenceData.schoolNames[691], "MSTA")
        XCTAssertEqual(SkillAssessmentReferenceData.schoolNames[953], "VLA")
        XCTAssertEqual(SkillAssessmentReferenceData.schoolNames[733], "West Whittier")
    }

    func testNameFixesTableHasTheFourKnownStudents() {
        XCTAssertEqual(SkillAssessmentReferenceData.nameFixes.count, 4)
        XCTAssertEqual(SkillAssessmentReferenceData.nameFixes["20222971"], "Maximiliano")
        XCTAssertEqual(SkillAssessmentReferenceData.nameFixes["20222657"], "Mahidevran")
        XCTAssertEqual(SkillAssessmentReferenceData.nameFixes["20222890"], "Liam")
        XCTAssertEqual(SkillAssessmentReferenceData.nameFixes["20220996"], "Christopher")
    }
}
