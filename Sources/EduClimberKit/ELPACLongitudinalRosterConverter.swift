import Foundation

/// Illuminate's "ELPAC Longitudinal Roster" export -> eduCLIMBER Tag Upload.
///
/// That export lists every Academic Year a student has taken the ELPAC,
/// nested under one header row per student (see `ELPACLongitudinalReader`
/// for the shape); a tag only wants to know where a student stands *now*, so
/// the reader collapses each student down to just their most recent Academic
/// Year before this converter ever sees the data. From there it's just a
/// student list like any other -- Student ID and name, deduplicated, with
/// the shared Student Roster as a fallback for anything missing, and School
/// Year/Tag Name/Tag Flag typed in once for the batch -- so that part is
/// simply delegated to a plain `TagUploadConverter` rather than duplicated.
public struct ELPACLongitudinalRosterConverter: AssessmentConverter {
    private let tagUpload: TagUploadConverter

    public init(rosterStoreURL: URL = StudentRosterStore.defaultStoreURL()) {
        self.tagUpload = TagUploadConverter(rosterStoreURL: rosterStoreURL)
    }

    public let key = "elpac_longitudinal_tag_upload"
    public let displayName = "ELPAC Longitudinal Roster (Tag Upload)"
    public let summary =
        "Builds an eduCLIMBER tag upload from an Illuminate ELPAC Longitudinal Roster export. "
        + "That export lists every Academic Year a student has taken the ELPAC, nested under a "
        + "header row per student -- this takes only each student's most recent Academic Year "
        + "(the Summative result when that year also has an Initial placeholder row), then "
        + "builds the tag exactly like a plain Tag Upload: Student ID and name, deduplicated, "
        + "with the shared Student Roster as a fallback for anything missing. School Year, Tag "
        + "Name, and Tag Flag are typed in once for the whole batch."

    public var prompts: [PromptField] { tagUpload.prompts }
    public var sourceColumns: [SourceColumn] { tagUpload.sourceColumns }
    public var outputColumns: [String] { tagUpload.outputColumns }

    public func loadSource(at url: URL) throws -> Table {
        try ELPACLongitudinalReader.read(contentsOf: url)
    }

    public func problems(for mapping: ColumnMapping) -> [String] {
        tagUpload.problems(for: mapping)
    }

    public func convert(
        table: Table, answers: [String: String], columns: [String: String?]
    ) throws -> ConversionResult {
        try tagUpload.convert(table: table, answers: answers, columns: columns)
    }

    public var defaultFileNameTemplate: String { tagUpload.defaultFileNameTemplate }

    public func defaultOutputName(answers: [String: String]) -> String {
        tagUpload.defaultOutputName(answers: answers)
    }
}
