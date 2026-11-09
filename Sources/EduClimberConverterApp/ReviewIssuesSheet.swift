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
///
/// "Fix & Remember…" is the other way out of a problem row: select it, type
/// in whatever's missing (Student ID, email, name, grade), and it's saved to
/// the shared Student Roster -- every converter's fallback, not just this
/// one -- then "Retry Conversion" re-runs the whole file with the fix applied.
///
/// A `ReviewRow` (currently just Eureka Math's not-yet-"done" attempts) is a
/// third, different kind of row: nothing is wrong with it -- every required
/// field converted cleanly -- the only question is whether the user wants it
/// in this export. Shown with its own checkbox per row plus Select All/None
/// for the common case of approving (or denying) everything at once; checked
/// rows join the export, unchecked rows are reported back to the caller as
/// denied so they can be written to a separate review file instead of lost.
final class ReviewIssuesSheet: NSWindowController {
    enum Decision {
        case skipAndContinue
        case retryConversion
        case cancel
    }

    private let result: ConversionResult
    private let fileName: String
    private var decision: Decision = .cancel
    private let problemsTable = NSTableView()
    private let noticesTable = NSTableView()
    private let reviewTable = NSTableView()
    private let fixButton = NSButton()
    private let retryButton = NSButton()
    private let fixStatusLabel: NSTextField = {
        let label = makeLabel("", secondary: true)
        label.maximumNumberOfLines = 3
        return label
    }()
    /// Row numbers the user has checked -- empty at first, since approving an
    /// unfinished attempt is a decision the user has to make, not a default.
    private var approvedRowNumbers: Set<Int> = []

    /// Runs the sheet modally. Returns what the user chose, plus (when they
    /// chose to continue) which `ReviewRow`s they checked -- by row number,
    /// matched against `result.reviewRows` to apply the decision.
    static func run(
        over parent: NSWindow, result: ConversionResult, fileName: String
    ) -> (decision: Decision, approvedReviewRowNumbers: Set<Int>) {
        let sheet = ReviewIssuesSheet(result: result, fileName: fileName)
        guard let window = sheet.window else { return (.cancel, []) }
        parent.beginSheet(window, completionHandler: nil)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        return (sheet.decision, sheet.approvedRowNumbers)
    }

    init(result: ConversionResult, fileName: String) {
        self.result = result
        self.fileName = fileName
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        window.title = !result.issues.isEmpty
            ? "Review Rows With Problems"
            : (result.reviewRows.isEmpty ? "Review Benchmark Notices" : "Review Rows Needing Approval")
        window.minSize = NSSize(width: 560, height: 380)
        super.init(window: window)
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeContentView() -> NSView {
        let skipped = result.skippedRowCount
        let usable = result.rows.count
        let pendingApproval = result.reviewRows.count
        let noticed = result.noticeIssues.count
        let source = fileName.isEmpty ? "this file" : fileName

        var headline: String
        if usable == 0 && pendingApproval == 0 {
            headline = "None of the rows in \(source) could be converted — "
                + "there is nothing to export. Fix the problems below and convert again."
        } else {
            headline = usable > 0
                ? "\(usable) row(s) in \(source) are ready to export."
                : "No rows in \(source) are ready to export yet."
            if skipped > 0 {
                headline += " \(skipped) row(s) have problems and cannot be converted.\n"
                    + "Skip them to export the rest, or cancel and fix the file first."
            }
            if pendingApproval > 0 {
                headline += "\n\(pendingApproval) row(s) converted cleanly but need your "
                    + "approval below -- check the ones to include; the rest are written to a "
                    + "separate review file instead of being exported."
            }
        }
        if noticed > 0 {
            headline += (usable == 0 && pendingApproval == 0) ? "" : "\n"
            headline += "\(noticed) row(s) have benchmark notices — informational only, "
                + "they are already included."
        }

        let headlineLabel = makeLabel(headline)
        headlineLabel.maximumNumberOfLines = 8
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
        if !result.reviewRows.isEmpty {
            sections.append(makeReviewSection())
        }

        let copyButton = NSButton(
            title: "Copy List", target: self, action: #selector(copyIssues))
        copyButton.bezelStyle = .rounded

        // Fixing a row here saves the correction to the shared Student
        // Roster (any assessment can use it from then on), rather than just
        // this one export -- so it's worth doing even when skipping the row
        // would otherwise be good enough for today.
        fixButton.title = "Fix & Remember…"
        fixButton.bezelStyle = .rounded
        fixButton.target = self
        fixButton.action = #selector(fixSelected)
        fixButton.isEnabled = false

        retryButton.title = "Retry Conversion"
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retryConversion)
        retryButton.isEnabled = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let spacer = NSView()
        var buttons: [NSView] = [copyButton]
        if !result.issues.isEmpty { buttons.append(fixButton) }
        buttons.append(contentsOf: [spacer, retryButton, cancelButton])
        if usable > 0 || pendingApproval > 0 {
            // With nothing to skip (notices only), this just acknowledges and
            // proceeds -- every usable row is already included either way.
            // Approved/denied status for the Needs Approval rows is read from
            // the checkboxes at the moment this is clicked, not baked into
            // the title -- the title only speaks to Problems rows, which are
            // always all-or-nothing (skip them or fix the file).
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

        let column = NSStackView(views: [headlineLabel] + sections + [fixStatusLabel, buttonRow])
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
            fixStatusLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
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

    /// The Needs Approval section: one checkbox per `ReviewRow`, plus a
    /// Select All/None pair for approving or denying everything at once --
    /// the individual checkboxes are still there for pulling just a few out
    /// of an otherwise all-approved (or all-denied) batch.
    private func makeReviewSection() -> NSView {
        let titleLabel = makeLabel("Needs Approval — check a row to include it in the export")
        titleLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = NSColor.systemBlue

        let approveColumn = NSTableColumn(identifier: .init("approve"))
        approveColumn.title = ""
        approveColumn.width = 28
        approveColumn.maxWidth = 28
        let studentColumn = NSTableColumn(identifier: .init("student"))
        studentColumn.title = "Student"
        studentColumn.width = 220
        let statusColumn = NSTableColumn(identifier: .init("status"))
        statusColumn.title = "Status"
        statusColumn.width = 340
        reviewTable.addTableColumn(approveColumn)
        reviewTable.addTableColumn(studentColumn)
        reviewTable.addTableColumn(statusColumn)
        reviewTable.dataSource = self
        reviewTable.delegate = self
        reviewTable.usesAlternatingRowBackgroundColors = true
        reviewTable.rowHeight = 20

        let scrollView = NSScrollView()
        scrollView.documentView = reviewTable
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

        let selectAllButton = NSButton(
            title: "Select All", target: self, action: #selector(selectAllReviewRows))
        selectAllButton.bezelStyle = .rounded
        let selectNoneButton = NSButton(
            title: "Select None", target: self, action: #selector(selectNoReviewRows))
        selectNoneButton.bezelStyle = .rounded
        let selectionRow = NSStackView(views: [selectAllButton, selectNoneButton])
        selectionRow.orientation = .horizontal
        selectionRow.spacing = 8

        let column = NSStackView(views: [titleLabel, scrollView, selectionRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        scrollView.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func issues(for tableView: NSTableView) -> [RowIssue] {
        tableView === noticesTable ? result.noticeIssues : result.issues
    }

    @objc private func toggleApproval(_ sender: NSButton) {
        guard result.reviewRows.indices.contains(sender.tag) else { return }
        let rowNumber = result.reviewRows[sender.tag].rowNumber
        if sender.state == .on {
            approvedRowNumbers.insert(rowNumber)
        } else {
            approvedRowNumbers.remove(rowNumber)
        }
    }

    @objc private func selectAllReviewRows() {
        approvedRowNumbers = Set(result.reviewRows.map(\.rowNumber))
        reviewTable.reloadData()
    }

    @objc private func selectNoReviewRows() {
        approvedRowNumbers.removeAll()
        reviewTable.reloadData()
    }

    @objc private func copyIssues() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.fullReport(), forType: .string)
    }

    @objc private func skipAndContinue() {
        decision = .skipAndContinue
        NSApp.stopModal()
    }

    @objc private func retryConversion() {
        decision = .retryConversion
        NSApp.stopModal()
    }

    @objc private func cancel() {
        decision = .cancel
        NSApp.stopModal()
    }

    /// Opens the fix sheet for the one selected problem row, and -- if the
    /// user saves something -- adds it to the shared Student Roster right
    /// away, so "Retry Conversion" picks it up immediately.
    @objc private func fixSelected() {
        guard let window,
              let row = problemsTable.selectedRowIndexes.first,
              result.issues.indices.contains(row)
        else { return }
        let issue = result.issues[row]
        let prefill = StudentRosterEntry.knownFields(fromErrorMessage: issue.problems.first ?? "")
        guard let entry = StudentFixSheet.run(
            over: window, problemSummary: issue.description, prefill: prefill)
        else { return }
        do {
            let existing = try StudentRosterStore.load()
            let merged = StudentRosterStore.upsert([entry], into: existing)
            try StudentRosterStore.save(merged.merged)
            fixStatusLabel.stringValue =
                "Saved to the Student Roster. Click \"Retry Conversion\" to apply it."
            retryButton.isEnabled = true
        } catch {
            fixStatusLabel.stringValue = "Could not save to the Student Roster: \(error.localizedDescription)"
        }
    }
}

extension ReviewIssuesSheet: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === reviewTable ? result.reviewRows.count : issues(for: tableView).count
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === problemsTable else { return }
        fixButton.isEnabled = problemsTable.selectedRowIndexes.count == 1
    }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        if tableView === reviewTable {
            return reviewRowView(for: tableColumn, row: row)
        }
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

    private func reviewRowView(for tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard result.reviewRows.indices.contains(row) else { return nil }
        let review = result.reviewRows[row]
        switch tableColumn?.identifier.rawValue {
        case "approve":
            let checkbox = NSButton(
                checkboxWithTitle: "", target: self, action: #selector(toggleApproval(_:)))
            checkbox.tag = row
            checkbox.state = approvedRowNumbers.contains(review.rowNumber) ? .on : .off
            return checkbox
        case "student":
            let label = NSTextField(labelWithString: review.label)
            label.lineBreakMode = .byTruncatingTail
            label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            return label
        case "status":
            let label = NSTextField(labelWithString: "Assessment Status: \(review.status)")
            label.lineBreakMode = .byTruncatingTail
            label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            return label
        default:
            return nil
        }
    }
}
