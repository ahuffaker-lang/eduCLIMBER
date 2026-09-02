import Foundation

/// The assessment-agnostic pipeline: read → match columns → map → write.
public enum Pipeline {
    /// Check the batch-wide prompt answers; returns a message per problem.
    public static func validateAnswers(
        converter: AssessmentConverter, answers: [String: String]
    ) -> [String] {
        converter.prompts.compactMap { $0.validate(answers[$0.key]) }
    }

    /// Read a CSV or Excel file.
    public static func loadSource(at url: URL) throws -> Table {
        switch url.pathExtension.lowercased() {
        case "xlsx", "xlsm", "xltx", "xltm":
            return try XLSXReader.read(contentsOf: url)
        case "csv", "txt", "tsv", "":
            return try CSVReader.read(contentsOf: url)
        case "xls":
            throw SourceFileError.legacyExcel
        case let other:
            throw SourceFileError.unsupportedType(other)
        }
    }

    /// Auto-match the converter's expected columns against this file's headers.
    /// Whatever comes back needing confirmation is what to put to the user.
    public static func matchColumns(
        converter: AssessmentConverter, table: Table
    ) -> ColumnMapping {
        resolveColumns(table: table, columns: converter.sourceColumns)
    }

    public static func convert(
        converter: AssessmentConverter,
        table: Table,
        answers: [String: String],
        mapping: ColumnMapping
    ) throws -> ConversionResult {
        let answerProblems = validateAnswers(converter: converter, answers: answers)
        if !answerProblems.isEmpty {
            throw ConverterError(answerProblems.joined(separator: "\n"))
        }
        let columnProblems = mapping.problems() + converter.problems(for: mapping)
        if !columnProblems.isEmpty {
            throw ConverterError(columnProblems.joined(separator: "\n"))
        }
        return try converter.convert(
            table: table, answers: answers, columns: mapping.asDictionary)
    }

    /// Read and convert in one step, for callers that cannot ask the user about
    /// columns: an unmatched header throws instead of prompting.
    public static func convertFile(
        converter: AssessmentConverter, url: URL, answers: [String: String]
    ) throws -> ConversionResult {
        let table = try loadSource(at: url)
        let mapping = matchColumns(converter: converter, table: table)
        if mapping.needsConfirmation || !converter.problems(for: mapping).isEmpty {
            let extra = converter.problems(for: mapping)
            let message = mapping.needsConfirmation
                ? ([mapping.unmatchedMessage()] + extra).joined(separator: "\n")
                : extra.joined(separator: "\n")
            throw ConverterError(message)
        }
        return try convert(converter: converter, table: table, answers: answers, mapping: mapping)
    }

    public static func save(result: ConversionResult, to url: URL) throws {
        try CSVWriter.write(columns: result.columns, rows: result.rows, to: url)
    }

    /// Default save location: next to the source file, with a descriptive name.
    public static func suggestedOutputURL(
        converter: AssessmentConverter, sourceURL: URL?, answers: [String: String]
    ) -> URL {
        let name = safeFileName(converter.defaultOutputName(answers: answers))
        let folder = sourceURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        return folder.appendingPathComponent(name)
    }

    public static func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_. "))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "converted.csv" : cleaned
    }

    public static func formatErrors(_ errors: [RowError]) -> String {
        errors.map(\.description).joined(separator: "\n")
    }
}
