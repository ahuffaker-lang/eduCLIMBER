import AppKit
import EduClimberKit

/// "Which of these is the real one?" -- shown when a converter finds the same
/// student submitted more than once in one file (e.g. the same assignment
/// pushed through two class rosters in Formative).
final class DuplicatePickerSheet: NSWindowController {
    private let table: Table
    private let groups: [[Int]]
    private let displayColumns: [String]
    private let converter: AssessmentConverter
    private var popUps: [NSPopUpButton] = []
    private var accepted = false

    /// Runs the sheet modally. Returns the chosen index *within each group*
    /// (`result[i]` picks `groups[i][result[i]]`), or nil if cancelled.
    static func run(
        over parent: NSWindow, table: Table, groups: [[Int]],
        displayColumns: [String], converter: AssessmentConverter
    ) -> [Int]? {
        let sheet = DuplicatePickerSheet(
            table: table, groups: groups, displayColumns: displayColumns, converter: converter)
        guard let window = sheet.window else { return nil }
        parent.beginSheet(window, completionHandler: nil)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        guard sheet.accepted else { return nil }
        return sheet.popUps.map(\.indexOfSelectedItem)
    }

    init(table: Table, groups: [[Int]], displayColumns: [String], converter: AssessmentConverter) {
        self.table = table
        self.groups = groups
        self.displayColumns = displayColumns
        self.converter = converter
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 360),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Resolve Duplicate Submissions"
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeContentView() -> NSView {
        let headline = makeLabel(
            "\(groups.count) student(s) have more than one submission in this file "
            + "(often the same assignment pushed through two class rosters). "
            + "Pick which one to keep for each.")
        headline.maximumNumberOfLines = 3
        headline.preferredMaxLayoutWidth = 620

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .leading
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        popUps = []
        for group in groups {
            let nameLabel = makeLabel(converter.duplicateGroupLabel(for: table, firstRowIndex: group[0]))
            let popUp = NSPopUpButton()
            popUp.addItems(withTitles: group.map(candidateLabel))
            popUp.widthAnchor.constraint(equalToConstant: 420).isActive = true
            popUps.append(popUp)
            grid.addRow(with: [nameLabel, popUp])
        }

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let acceptButton = NSButton(title: "Use These", target: self, action: #selector(accept))
        acceptButton.bezelStyle = .rounded
        acceptButton.keyEquivalent = "\r"
        let spacer = NSView()
        let buttonRow = NSStackView(views: [spacer, cancelButton, acceptButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let column = NSStackView(views: [headline, grid, buttonRow])
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
            headline.widthAnchor.constraint(equalTo: column.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        return root
    }

    /// e.g. "ELA and Social Studies - St. John · Andrea St. John ·
    /// 10/2/2026, 9:27:26 AM · 88" -- whatever columns the converter says
    /// distinguish one candidate row from another.
    private func candidateLabel(for rowIndex: Int) -> String {
        let row = table.rows[rowIndex]
        let parts = displayColumns.map { column -> String in
            let value = table.value(row, table.findColumn([column]))
            return value.isEmpty ? "—" : value
        }
        return parts.joined(separator: " · ")
    }

    @objc private func accept() {
        accepted = true
        NSApp.stopModal()
    }

    @objc private func cancel() {
        accepted = false
        NSApp.stopModal()
    }
}
