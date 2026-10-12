import Foundation

/// Reference data the Skill Assessment converter needs beyond what's in any
/// one export: how Aeries codes map to what eduCLIMBER expects, and students
/// whose name is already known to be missing from every export seen so far.
public enum SkillAssessmentReferenceData {
    /// Aeries grade code -> eduCLIMBER grade value. `nil` for a code nothing
    /// here recognizes, which is flagged for review rather than guessed at.
    public static func eduClimberGrade(forAeriesCode code: Int) -> String? {
        if code == -1 { return "TK" }
        if code == 0 { return "K" }
        if code > 0 { return String(code) }
        return nil
    }

    /// Aeries school code -> the name eduCLIMBER expects, spelled exactly as
    /// the district does (capitalization and spacing included).
    public static let schoolNames: [Int: String] = [
        626: "Sorensen", 634: "Phelan", 659: "Edwards", 667: "Longfellow",
        675: "Hoover", 683: "Jackson", 691: "MSTA", 709: "Andrews",
        717: "Orange Grove", 725: "Dexter", 733: "West Whittier", 953: "VLA",
    ]

    /// Students whose export name arrives as "Last, " with no first name --
    /// confirmed missing on every Skill Assessment Student List export seen
    /// so far (two different skills, same four students), so the fix is kept
    /// here rather than per-assessment. Keyed by Student ID.
    public static let nameFixes: [String: String] = [
        "20222971": "Maximiliano",
        "20222657": "Mahidevran",
        "20222890": "Liam",
        "20220996": "Christopher",
    ]
}
