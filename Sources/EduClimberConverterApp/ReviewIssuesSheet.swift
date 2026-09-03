import AppKit
import EduClimberKit

/// Shows what is wrong with the source file and lets the user decide: skip the
/// suspect rows and export the rest, or stop and fix the file.
///
/// Real exports have blank and half-filled rows in them. Refusing to convert
/// anything because of a handful of them turns a two-minute job into a
/// spreadsheet hunt, so the choice belongs to the user. Benchmark notices --
/// where the sheet's own Proficiency Level disagreed with the rubric -- are
/// shown the same way, but never block anything: the row already converted
/// with the rubric's value, and this is just the chance to see why.
final class ReviewIssuesSheet: NSWindowController {
    enum Decision {
        case skipAndContinue
        case cancel
    }

    private let result: ConversionResult
    private let fileName: String
    private var decision: Decision = .cancel
    private let problemsTable = NSTableView()
    private let noticesTable = NSTableView()

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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        window.title = result.issues.isEmpty ? "Review Benchmark Notices" : "Review Rows With Problems"
        window.minSize = NSSize(width: 560, height: 380)
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeContentView() -> NSView {
        let skipped = result.skippedRowCount
        let usable = result.rows.count
        let noticed = result.noticeIssues.count
        let source = fileName.isEmpty ? "this file" : fileName

        var headline: String
        if usable == 0 {
            headline = "None of the rows in \(source) could be converted — "
                + "there is nothing to export. Fix the problems below and convert again."
        } else {
            headline = "\(usable) row(s) in \(source) are ready to export."
            if skipped > 0 {
                headline += " \(skipped) row(s) have problems and cannot be converted.\n"
                    + "Skip them to export the other \(usable), or cancel and fix the file first."
            }
        }
        if noticed > 0 {
            headline += usable == 0 ? "" : "\n"
            headline += "\(noticed) row(s) have benchmark notices — informational only, "
                + "they are already included."
        }

        let headlineLabel = makeLabel(headline)
        headlineLabel.maximumNumberOfLines = 6
        headlineLabel.preferredMaxLayoutWidth = 640

        var sections: [NSView] = []
        if !result.noticeIssues.isEmpty {
            sections.append(makeSection(
                title: "Benchmark Notices — included, not blocking",
                titleColor: NSColor.systemOrange,
                table: noticesTable, rowColumnTitle: "Row", issueColumnTitle: "Notice"))
        }
        if !result.issues.isEmpty {
            sections.append(makeSection(
                title: "Problems — must skip or fix",
                titleColor: NSColor.systemRed,
                table: problemsTable, rowColumnTitle: "Row", issueColumnTitle: "Problem"))
        }

        let copyButton = NSButton(
            title: "Copy List", target: self, action: #selector(copyIssues))
        copyButton.bezelStyle = .rounded
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let spacer = NSView()
        var buttons: [NSView] = [copyButton, spacer, cancelButton]
        if usable > 0 {
            // With nothing to skip (notices only), this just acknowledges and
            // proceeds -- every usable row is already included either way.
            let continueTitle = skipped > 0 ? "Skip \(skipped) Row(s) and Continue" : "Continue"
            let continueButton = NSButton(
                title: continueTitle, target: self, action: #selector(skipAndContinue))
            continueButton.bezelStyle = .rounded
            continueButton.keyEquivalent = "\r"
            buttons.append(continueButton)
        }
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let column = NSStackView(views: [headlineLabel] + sections + [buttonRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(column)
        var constraints = [
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            headlineLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ]
        for section in sections {
            constraints.append(section.widthAnchor.constraint(equalTo: column.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return root
    }

    /// One labeled, scrollable row list -- used for both Notices and Problems so
    /// the two read as the same kind of thing, distinguished by color and title.
    private func makeSection(
        title: String, titleColor: NSColor, table: NSTableView,
        rowColumnTitle: String, issueColumnTitle: String
    ) -> NSView {
        let titleLabel = makeLabel(title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = titleColor

        let rowColumn = NSTableColumn(identifier: .init("row"))
        rowColumn.title = rowColumnTitle
        rowColumn.width = 60
        rowColumn.maxWidth = 90
        let issueColumn = NSTableColumn(identifier: .init("issue"))
        issueColumn.title = issueColumnTitle
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
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let column = NSStackView(views: [titleLabel, scrollView])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        scrollView.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func issues(for tableView: NSTableView) -> [RowIssue] {
        tableView === noticesTable ? result.noticeIssues : result.issues
    }

    @objc private func copyIssues() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.fullReport(), forType: .string)
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
    func numberOfRows(in tableView: NSTableView) -> Int { issues(for: tableView).count }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        let list = issues(for: tableView)
        guard list.indices.contains(row) else { return nil }
        let issue = list[row]
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
