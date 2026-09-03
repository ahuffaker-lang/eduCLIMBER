import Foundation

/// The benchmark tables the app ships with, and the logic that picks one for a
/// given language + school year.
///
/// Each cell's data is transcribed verbatim from the district's own benchmark
/// sheets; `Resources/Benchmarks/*.csv` holds the same data as a plain,
/// human-diffable reference, and a test asserts the two never drift apart.
public enum BenchmarkRegistry {

    static let english2019Cells: [String: [String: BenchmarkCell]] = [
        "Kinder": [
            "T1": .noScale,
            "T2": BenchmarkCell([BenchmarkBand(4, "D or above"), BenchmarkBand(3, "C"), BenchmarkBand(2, "A/B"), BenchmarkBand(1, "Early Emergent")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "E or above"), BenchmarkBand(3, "D"), BenchmarkBand(2, "C"), BenchmarkBand(1, "B or below")]),
        ],
        "Grade 1": [
            "T1": BenchmarkCell([BenchmarkBand(4, "G or above"), BenchmarkBand(3, "E/F"), BenchmarkBand(2, "D"), BenchmarkBand(1, "C or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "J or above"), BenchmarkBand(3, "G/H/I"), BenchmarkBand(2, "F"), BenchmarkBand(1, "E or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "K or above"), BenchmarkBand(3, "I/J"), BenchmarkBand(2, "G/H"), BenchmarkBand(1, "F or below")]),
        ],
        "Grade 2": [
            "T1": BenchmarkCell([BenchmarkBand(4, "L or above"), BenchmarkBand(3, "J/K"), BenchmarkBand(2, "H/I"), BenchmarkBand(1, "G or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "M or above"), BenchmarkBand(3, "K/L"), BenchmarkBand(2, "I/J"), BenchmarkBand(1, "H or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "N or above"), BenchmarkBand(3, "L/M"), BenchmarkBand(2, "J/K"), BenchmarkBand(1, "I or below")]),
        ],
        "Grade 3": [
            "T1": BenchmarkCell([BenchmarkBand(4, "O or above"), BenchmarkBand(3, "N"), BenchmarkBand(2, "L/M"), BenchmarkBand(1, "K or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "P or above"), BenchmarkBand(3, "O"), BenchmarkBand(2, "N"), BenchmarkBand(1, "M or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "Q or above"), BenchmarkBand(3, "P"), BenchmarkBand(2, "O"), BenchmarkBand(1, "N or below")]),
        ],
        "Grade 4": [
            "T1": BenchmarkCell([BenchmarkBand(4, "S or above"), BenchmarkBand(3, "Q/R"), BenchmarkBand(2, "O/P"), BenchmarkBand(1, "N or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "R/S"), BenchmarkBand(2, "P/Q"), BenchmarkBand(1, "O or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "S"), BenchmarkBand(2, "Q/R"), BenchmarkBand(1, "P or below")]),
        ],
        "Grade 5": [
            "T1": BenchmarkCell([BenchmarkBand(4, "U or above"), BenchmarkBand(3, "S/T"), BenchmarkBand(2, "Q/R"), BenchmarkBand(1, "P or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "V or above"), BenchmarkBand(3, "U"), BenchmarkBand(2, "S/T"), BenchmarkBand(1, "R or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "W or above"), BenchmarkBand(3, "U/V"), BenchmarkBand(2, "T"), BenchmarkBand(1, "S or below")]),
        ],
    ]


    static let english2026Cells: [String: [String: BenchmarkCell]] = [
        "Kinder": [
            "T1": .noScale,
            "T2": BenchmarkCell([BenchmarkBand(4, "D or above"), BenchmarkBand(3, "C"), BenchmarkBand(2, "A/B"), BenchmarkBand(1, "Early Emergent")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "F or above"), BenchmarkBand(3, "D/E"), BenchmarkBand(2, "C"), BenchmarkBand(1, "B or below")]),
        ],
        "Grade 1": [
            "T1": BenchmarkCell([BenchmarkBand(4, "F or above"), BenchmarkBand(3, "D/E"), BenchmarkBand(2, "C"), BenchmarkBand(1, "B or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "K or above"), BenchmarkBand(3, "H/I/J"), BenchmarkBand(2, "F/G"), BenchmarkBand(1, "E or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "L or above"), BenchmarkBand(3, "I/J/K"), BenchmarkBand(2, "G/H"), BenchmarkBand(1, "F or below")]),
        ],
        "Grade 2": [
            "T1": BenchmarkCell([BenchmarkBand(4, "L or above"), BenchmarkBand(3, "I/J/K"), BenchmarkBand(2, "G/H"), BenchmarkBand(1, "F or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "N or above"), BenchmarkBand(3, "L/M"), BenchmarkBand(2, "J/K"), BenchmarkBand(1, "I or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "N or above"), BenchmarkBand(3, "M"), BenchmarkBand(2, "K/L"), BenchmarkBand(1, "J or below")]),
        ],
        "Grade 3": [
            "T1": BenchmarkCell([BenchmarkBand(4, "N or above"), BenchmarkBand(3, "M"), BenchmarkBand(2, "K/L"), BenchmarkBand(1, "J or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "P or above"), BenchmarkBand(3, "O"), BenchmarkBand(2, "N"), BenchmarkBand(1, "M or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "Q or above"), BenchmarkBand(3, "P"), BenchmarkBand(2, "O"), BenchmarkBand(1, "N or below")]),
        ],
        "Grade 4": [
            "T1": BenchmarkCell([BenchmarkBand(4, "Q or above"), BenchmarkBand(3, "P"), BenchmarkBand(2, "O"), BenchmarkBand(1, "N or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "R/S"), BenchmarkBand(2, "P/Q"), BenchmarkBand(1, "O or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "S"), BenchmarkBand(2, "Q/R"), BenchmarkBand(1, "P or below")]),
        ],
        "Grade 5": [
            "T1": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "S"), BenchmarkBand(2, "Q/R"), BenchmarkBand(1, "P or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "V or above"), BenchmarkBand(3, "U"), BenchmarkBand(2, "S/T"), BenchmarkBand(1, "R or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "W or above"), BenchmarkBand(3, "U/V"), BenchmarkBand(2, "T"), BenchmarkBand(1, "S or below")]),
        ],
    ]


    static let spanish2021Cells: [String: [String: BenchmarkCell]] = [
        "Kinder": [
            "T1": .noScale,
            "T2": BenchmarkCell([BenchmarkBand(4, "C or above"), BenchmarkBand(3, "B"), BenchmarkBand(2, "A"), BenchmarkBand(1, "Early Emergent")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "E or above"), BenchmarkBand(3, "D"), BenchmarkBand(2, "B/C"), BenchmarkBand(1, "A or below")]),
        ],
        "Grade 1": [
            "T1": BenchmarkCell([BenchmarkBand(4, "G or above"), BenchmarkBand(3, "E/F"), BenchmarkBand(2, "D"), BenchmarkBand(1, "C or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "J or above"), BenchmarkBand(3, "G/H/I"), BenchmarkBand(2, "F"), BenchmarkBand(1, "E or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "K or above"), BenchmarkBand(3, "I/J"), BenchmarkBand(2, "G/H"), BenchmarkBand(1, "F or below")]),
        ],
        "Grade 2": [
            "T1": BenchmarkCell([BenchmarkBand(4, "L or above"), BenchmarkBand(3, "J/K"), BenchmarkBand(2, "H/I"), BenchmarkBand(1, "G or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "M or above"), BenchmarkBand(3, "K/L"), BenchmarkBand(2, "I/J"), BenchmarkBand(1, "H or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "N or above"), BenchmarkBand(3, "L/M"), BenchmarkBand(2, "J/K"), BenchmarkBand(1, "I or below")]),
        ],
        "Grade 3": [
            "T1": BenchmarkCell([BenchmarkBand(4, "O or above"), BenchmarkBand(3, "N"), BenchmarkBand(2, "L/M"), BenchmarkBand(1, "K or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "P or above"), BenchmarkBand(3, "O"), BenchmarkBand(2, "N"), BenchmarkBand(1, "M or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "Q or above"), BenchmarkBand(3, "P"), BenchmarkBand(2, "O"), BenchmarkBand(1, "N or below")]),
        ],
        "Grade 4": [
            "T1": BenchmarkCell([BenchmarkBand(4, "S or above"), BenchmarkBand(3, "Q/R"), BenchmarkBand(2, "O/P"), BenchmarkBand(1, "N or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "R/S"), BenchmarkBand(2, "P/Q"), BenchmarkBand(1, "O or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "T or above"), BenchmarkBand(3, "S"), BenchmarkBand(2, "Q/R"), BenchmarkBand(1, "P or below")]),
        ],
        "Grade 5": [
            "T1": BenchmarkCell([BenchmarkBand(4, "U or above"), BenchmarkBand(3, "S/T"), BenchmarkBand(2, "Q/R"), BenchmarkBand(1, "P or below")]),
            "T2": BenchmarkCell([BenchmarkBand(4, "V or above"), BenchmarkBand(3, "U"), BenchmarkBand(2, "S/T"), BenchmarkBand(1, "R or below")]),
            "T3": BenchmarkCell([BenchmarkBand(4, "W or above"), BenchmarkBand(3, "U/V"), BenchmarkBand(2, "T"), BenchmarkBand(1, "S or below")]),
        ],
    ]
    public static let rubrics: [BenchmarkRubric] = [
        BenchmarkRubric(
            language: "English", label: "English 2019-20",
            effectiveFromYear: nil, cells: english2019Cells),
        BenchmarkRubric(
            language: "English", label: "English 2026-27",
            effectiveFromYear: 2026, cells: english2026Cells),
        BenchmarkRubric(
            language: "Spanish", label: "Spanish 2021-22",
            effectiveFromYear: nil, cells: spanish2021Cells),
    ]

    /// The rubric chosen for a language + "YYYY-YYYY" school year, and whether that
    /// rubric was built for an earlier year than the one requested (a dated rubric
    /// carried forward because nothing newer has been loaded yet).
    public struct Selection {
        public let rubric: BenchmarkRubric
        public let isCarriedForward: Bool
        public let requestedStartYear: Int?
    }

    /// Picks the rubric for `language` + `schoolYear`, or nil if the language is not
    /// recognized at all. In practice both Language options always resolve to a
    /// rubric -- English falls back to the pre-2026-27 table, Spanish has only one
    /// table -- so this only returns nil for a language nothing has been loaded for.
    public static func select(language: String, schoolYear: String) -> Selection? {
        let requestedStartYear = Int(schoolYear.prefix(4))
        let candidates = rubrics.filter { $0.language.caseInsensitiveCompare(language) == .orderedSame }
        guard !candidates.isEmpty else { return nil }

        // Eligible: a rubric with no lower bound (applies unless something more
        // specific supersedes it), or a dated rubric effective at or before the
        // requested year. Among those, the most specific (latest effective year)
        // wins; a dated rubric always outranks an undated one when both qualify.
        let eligible = candidates.filter { rubric in
            guard let effective = rubric.effectiveFromYear, let requested = requestedStartYear else {
                return true
            }
            return effective <= requested
        }
        guard let chosen = eligible.max(by: { ($0.effectiveFromYear ?? Int.min) < ($1.effectiveFromYear ?? Int.min) })
        else { return nil }

        let isCarriedForward: Bool
        if let effective = chosen.effectiveFromYear, let requested = requestedStartYear {
            isCarriedForward = effective < requested
        } else {
            isCarriedForward = false
        }
        return Selection(rubric: chosen, isCarriedForward: isCarriedForward, requestedStartYear: requestedStartYear)
    }
}
