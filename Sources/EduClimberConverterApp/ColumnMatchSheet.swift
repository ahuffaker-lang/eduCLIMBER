import AppKit
import EduClimberKit

/// "Which column in your file is this?" -- shown as a sheet when a header is
/// misspelled, renamed or missing, and on demand to review the auto-matches.
final class ColumnMatchSheet: NSWindowController {
    private var mapping: ColumnMapping
    private let converter: AssessmentConverter
    private let fileName: String
    private var popUps: [String: NSPopUpButton] = [:]
    private var accepted = false

    /// Runs the sheet modally. Returns true when the user accepted the choices,
    /// which are written back into `mapping`.
    static func run(
        over parent: NSWindow,
        mapping: inout ColumnMapping,
        converter: AssessmentConverter,
        fileName: String
    ) -> Bool {
        let sheet = ColumnMatchSheet(mapping: mapping, converter: converter, fileName: fileName)
        guard let window = sheet.window else { return false }
        parent.beginSheet(window, completionHandler: nil)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        if sheet.accepted {
            mapping = sheet.mapping
            return true
        }
        return false
    }

    init(mapping: ColumnMapping, converter: AssessmentConverter, fileName: String) {
        self.mapping = mapping
        self.converter = converter
        self.fileName = fileName
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.title = "Match Columns"
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeContentView() -> NSView {
        var unmatched = mapping.unsettled.map(\.column.label)
        var headline: String
        let converterProblems = converter.problems(for: mapping)
        if unmatched.isEmpty && !converterProblems.isEmpty {
            // Nothing is individually missing, but the converter still needs
            // something -- e.g. a name column in one shape or the other.
            unmatched = []
        }
        if unmatched.isEmpty {
            headline = "Every expected column was matched automatically. Change any of "
                + "them here if a column was matched to the wrong header."
        } else {
            let inFile = fileName.isEmpty ? "" : " in \(fileName)"
            headline = "Some columns could not be matched automatically\(inFile):\n"
                + unmatched.joined(separator: ", ")
                + "\n\nPick the column from your file that holds each one. The closest "
                + "match is pre-selected — change it if it's wrong."
        }

        if !converterProblems.isEmpty {
            headline = converterProblems.joined(separator: "\n") + "\n\n" + headline
        }
        let headlineLabel = makeLabel(headline)
        headlineLabel.maximumNumberOfLines = 6
        headlineLabel.preferredMaxLayoutWidth = 600

        let grid = NSGridView(numberOfColumns: 3, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .leading
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.addRow(with: [
            makeHeaderLabel("Expected column"),
            makeHeaderLabel("Column in your file"),
            makeHeaderLabel(""),
        ])

        for match in mapping.matches {
            let label = makeLabel(
                match.column.label + (match.column.isRequired ? "" : "  (optional)"))

            let popUp = NSPopUpButton()
            popUp.addItems(withTitles: mapping.headers + [notInFileLabel])
            popUp.selectItem(withTitle: match.bestGuess ?? notInFileLabel)
            popUp.widthAnchor.constraint(equalToConstant: 260).isActive = true
            popUps[match.column.key] = popUp

            var note = match.isSettled ? "" : "needs checking"
            if !match.column.example.isEmpty {
                note += (note.isEmpty ? "" : " · ") + "e.g. \(match.column.example)"
            }
            grid.addRow(with: [label, popUp, makeLabel(note, secondary: true)])
        }

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let acceptButton = NSButton(
            title: "Use These Columns", target: self, action: #selector(accept))
        acceptButton.bezelStyle = .rounded
        acceptButton.keyEquivalent = "\r"

        let spacer = NSView()
        let buttonRow = NSStackView(views: [spacer, cancelButton, acceptButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let column = NSStackView(views: [headlineLabel, grid, buttonRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            headlineLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        return root
    }

    private func makeHeaderLabel(_ text: String) -> NSTextField {
        let label = makeLabel(text)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }

    /// The user's picks, with the "not in this file" entry meaning nil.
    func choices() -> [String: String?] {
        var result: [String: String?] = [:]
        for (key, popUp) in popUps {
            let title = popUp.titleOfSelectedItem ?? notInFileLabel
            result[key] = title == notInFileLabel ? nil : title
        }
        return result
    }

    @objc private func accept() {
        var candidate = mapping
        candidate.apply(choices())
        let problems = candidate.problems() + converter.problems(for: candidate)
        guard problems.isEmpty else {
            // Leave the mapping untouched so the user can fix their picks.
            let alert = NSAlert()
            alert.messageText = "Match Columns"
            alert.informativeText = problems.joined(separator: "\n")
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        mapping = candidate
        accepted = true
        NSApp.stopModal()
    }

    @objc private func cancel() {
        accepted = false
        NSApp.stopModal()
    }
}
