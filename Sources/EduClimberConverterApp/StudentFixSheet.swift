import AppKit
import EduClimberKit

/// "Fix & Remember…" -- lets the user type in whatever they know about a
/// student right where they're looking at the problem, instead of hunting
/// down a separate file to fix and re-upload. Whatever they enter here is
/// saved to the shared Student Roster, so it's filled in automatically for
/// this student on every future conversion, not just this one row.
final class StudentFixSheet: NSWindowController {
    private var accepted = false
    private let studentIDField = NSTextField()
    private let emailField = NSTextField()
    private let firstNameField = NSTextField()
    private let lastNameField = NSTextField()
    private let gradeField = NSTextField()

    /// Runs the sheet modally. Returns the entry to save, or nil if the user
    /// cancelled or left every field blank.
    static func run(over parent: NSWindow, problemSummary: String) -> StudentRosterEntry? {
        let sheet = StudentFixSheet(problemSummary: problemSummary)
        guard let window = sheet.window else { return nil }
        parent.beginSheet(window, completionHandler: nil)
        NSApp.runModal(for: window)
        parent.endSheet(window)
        window.orderOut(nil)
        guard sheet.accepted else { return nil }
        let entry = StudentRosterEntry(
            studentID: sheet.studentIDField.stringValue.trimmingCharacters(in: .whitespaces),
            email: sheet.emailField.stringValue.trimmingCharacters(in: .whitespaces),
            firstName: sheet.firstNameField.stringValue.trimmingCharacters(in: .whitespaces),
            lastName: sheet.lastNameField.stringValue.trimmingCharacters(in: .whitespaces),
            grade: sheet.gradeField.stringValue.trimmingCharacters(in: .whitespaces))
        return entry.isBlank ? nil : entry
    }

    init(problemSummary: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Fix & Remember"
        super.init(window: window)
        window.contentView = makeContentView(problemSummary: problemSummary)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeContentView(problemSummary: String) -> NSView {
        let headline = makeLabel(
            "Fill in whatever you know for this student. It's saved to the Student Roster, so "
            + "it's used automatically next time too -- for any assessment, not just this one.")
        headline.maximumNumberOfLines = 4
        headline.preferredMaxLayoutWidth = 420

        let problemLabel = makeLabel(problemSummary, secondary: true)
        problemLabel.maximumNumberOfLines = 3
        problemLabel.preferredMaxLayoutWidth = 420

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .leading
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        for (label, field) in [
            ("Student ID:", studentIDField), ("Email:", emailField),
            ("First Name:", firstNameField), ("Last Name:", lastNameField),
            ("Grade:", gradeField),
        ] {
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
            grid.addRow(with: [makeLabel(label), field])
        }

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let spacer = NSView()
        let buttonRow = NSStackView(views: [spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let column = NSStackView(views: [headline, problemLabel, grid, buttonRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            headline.widthAnchor.constraint(equalTo: column.widthAnchor),
            problemLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        return root
    }

    @objc private func save() {
        accepted = true
        NSApp.stopModal()
    }

    @objc private func cancel() {
        accepted = false
        NSApp.stopModal()
    }
}
