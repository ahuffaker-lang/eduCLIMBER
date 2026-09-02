import AppKit
import EduClimberKit

/// Shows what is wrong with the source file and lets the user decide: skip the
/// suspect rows and export the rest, or stop and fix the file.
///
/// Real exports have blank and half-filled rows in them. Refusing to convert
/// anything because of a handful of them turns a two-minute job into a
/// spreadsheet hunt, so the choice belongs to the user.
final class ReviewIssuesSheet: NSWindowController {
    enum Decision {
        case skipAndContinue
        case cancel
    }

    private let result: ConversionResult
    private let fileName: String
    private var decision: Decision = .cancel
    private let table = NSTableView()

    /// Runs the sheet modally and returns what the user chose.
    static func run(over parent: NSWindow, result: ConversionResult, fileName: String) -> Decision {
        let sheet = ReviewIssuesSheet(result: result, fileName: fileName)
        guard let window = sheet.window else { return .cancel }
        parent.beginSheet(window, completionHandler: nil)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return sheet.decision
    }

    init(result: ConversionResult, fileName: String) {
        self.result = result
        self.fileName = fileName
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 460),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Review Rows With Problems"
        window.minSize = NSSize(width: 560, height: 360)
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeContentView() -> NSView {
        let skipped = result.skippedRowCount
        let usable = result.rows.count
        let source = fileName.isEmpty ? "this file" : fileName
        let headline: String
        if usable == 0 {
            headline = "None of the rows in \(source) could be converted — "
                + "there is nothing to export. Fix the problems below and convert again."
        } else {
            headline = "\(usable) row(s) in \(source) are ready to export. "
                + "\(skipped) row(s) have problems and cannot be converted.\n"
                + "Skip them to export the other \(usable), or cancel and fix the file first."
        }
        let headlineLabel = makeLabel(headline)
        headlineLabel.maximumNumberOfLines = 4
        headlineLabel.preferredMaxLayoutWidth = 640

        // The issue list.
        let rowColumn = NSTableColumn(identifier: .init("row"))
        rowColumn.title = "Row"
        rowColumn.width = 60
        rowColumn.maxWidth = 90
        let issueColumn = NSTableColumn(identifier: .init("issue"))
        issueColumn.title = "Problem"
        issueColumn.width = 560
        table.addTableColumn(rowColumn)
        table.addTableColumn(issueColumn)
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.rowHeight = 20

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = NSButton(
            title: "Copy List", target: self, action: #selector(copyIssues))
        copyButton.bezelStyle = .rounded
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let spacer = NSView()
        var buttons: [NSView] = [copyButton, spacer, cancelButton]
        if usable > 0 {
            let continueButton = NSButton(
                title: "Skip \(skipped) Row(s) and Continue",
                target: self, action: #selector(skipAndContinue))
            continueButton.bezelStyle = .rounded
            continueButton.keyEquivalent = "\r"
            buttons.append(continueButton)
        }
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let column = NSStackView(views: [headlineLabel, scrollView, buttonRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            headlineLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            buttonRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        return root
    }

    @objc private func copyIssues() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.issuesReport(), forType: .string)
    }

    @objc private func skipAndContinue() {
        decision = .skipAndContinue
        NSApp.stopModal()
    }

    @objc private func cancel() {
        decision = .cancel
        NSApp.stopModal()
    }
}

extension ReviewIssuesSheet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { result.issues.count }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard result.issues.indices.contains(row) else { return nil }
        let issue = result.issues[row]
        let text = tableColumn?.identifier.rawValue == "row"
            ? String(issue.rowNumber)
            : issue.summary
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.toolTip = issue.description
        return label
    }
}
