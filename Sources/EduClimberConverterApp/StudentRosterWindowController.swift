import AppKit
import UniformTypeIdentifiers

import EduClimberKit

/// Lets the user build up the persisted, shared Student Roster by hand --
/// paste rows copied from Excel, or import a CSV. Stays open on its own,
/// independent of the main window -- not a sheet -- since the natural
/// workflow is "add a fact whenever I come across one," the same as the
/// Formative ID Matches window. Every converter consults this roster as a
/// fallback before flagging a row, so a fix added here (or from the "Fix &
/// Remember…" button in a review window) covers every assessment type, not
/// just the one being converted when it was added.
final class StudentRosterWindowController: NSWindowController, NSTableViewDataSource {
    private let storeURL: URL
    private var entries: [StudentRosterEntry] = []
    private let tableView = NSTableView()
    private let statusLabel = makeLabel("", secondary: true)
    private let pasteTextView = NSTextView()

    init(storeURL: URL = StudentRosterStore.defaultStoreURL()) {
        self.storeURL = storeURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Student Roster"
        window.minSize = NSSize(width: 560, height: 440)
        super.init(window: window)
        window.contentView = makeContentView()
        loadFromDisk()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let explanation = makeLabel(
            "Every converter checks here before giving up on a row that's missing a Student ID, "
            + "email, name, or grade -- so a fix added here (or from a conversion's review window) "
            + "covers every assessment, not just the one you're working on. Add entries by pasting "
            + "columns copied from Excel, or by importing a CSV.",
            secondary: true)
        explanation.maximumNumberOfLines = 5

        for (identifier, title, width) in [
            ("studentID", "Student ID", CGFloat(110)), ("email", "Email", CGFloat(180)),
            ("firstName", "First Name", CGFloat(100)), ("lastName", "Last Name", CGFloat(120)),
            ("grade", "Grade", CGFloat(60)),
        ] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true

        let tableScrollView = NSScrollView()
        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.borderType = .bezelBorder
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false
        tableView.autoresizingMask = [.width]

        let deleteButton = NSButton(
            title: "Delete Selected", target: self, action: #selector(deleteSelected))
        deleteButton.bezelStyle = .rounded
        let matchesBox = makeBox(title: "Known Students", views: [tableScrollView, deleteButton])

        pasteTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pasteTextView.isRichText = false
        let pasteScrollView = NSScrollView()
        pasteScrollView.documentView = pasteTextView
        pasteScrollView.hasVerticalScroller = true
        pasteScrollView.borderType = .bezelBorder
        pasteScrollView.translatesAutoresizingMaskIntoConstraints = false
        pasteTextView.autoresizingMask = [.width]

        let pasteHint = makeLabel(
            "One per line: Student ID, Email, First Name, Last Name, Grade -- tab- or "
            + "comma-separated. Leave a field blank if you don't know it yet.", secondary: true)
        let addPastedButton = NSButton(
            title: "Add Pasted Rows", target: self, action: #selector(addPastedRows))
        addPastedButton.bezelStyle = .rounded
        let importButton = NSButton(
            title: "Import CSV…", target: self, action: #selector(importCSV))
        importButton.bezelStyle = .rounded
        let addButtonRow = NSStackView(views: [addPastedButton, importButton])
        addButtonRow.orientation = .horizontal
        addButtonRow.spacing = 8
        let addBox = makeBox(title: "Add Students", views: [pasteHint, pasteScrollView, addButtonRow])

        let column = NSStackView(views: [explanation, matchesBox, addBox, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            explanation.widthAnchor.constraint(equalTo: column.widthAnchor),
            matchesBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            addBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            tableScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            pasteScrollView.heightAnchor.constraint(equalToConstant: 80),
        ])
        return root
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard entries.indices.contains(row) else { return nil }
        let entry = entries[row]
        switch tableColumn?.identifier.rawValue {
        case "studentID": return entry.studentID
        case "email": return entry.email
        case "firstName": return entry.firstName
        case "lastName": return entry.lastName
        case "grade": return entry.grade
        default: return nil
        }
    }

    // MARK: - Actions

    @objc private func addPastedRows() {
        let incoming = StudentRosterStore.parse(pastedText: pasteTextView.string)
        guard !incoming.isEmpty else {
            setStatus(
                "No valid rows found. Expected one per line: Student ID, Email, First Name, "
                + "Last Name, Grade, separated by a tab or comma.")
            return
        }
        applyMerge(incoming: incoming)
        pasteTextView.string = ""
    }

    @objc private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import Student Roster"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.importableTypes
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try StudentRosterStore.loadEntries(fromFile: url)
            guard !incoming.isEmpty else {
                setStatus("No valid rows found in \(url.lastPathComponent).")
                return
            }
            applyMerge(incoming: incoming)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Import \(url.lastPathComponent)"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private static let importableTypes: [UTType] = {
        let names = ["csv", "tsv", "txt", "xlsx", "xls"]
        var types = names.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.commaSeparatedText, .plainText, .spreadsheet, .data])
        var seen = Set<String>()
        return types.filter { seen.insert($0.identifier).inserted }
    }()

    @objc private func deleteSelected() {
        let indices = tableView.selectedRowIndexes
        guard !indices.isEmpty else { return }
        for index in indices.sorted(by: >) {
            entries.remove(at: index)
        }
        tableView.reloadData()
        persistAndReport(message: "Deleted \(indices.count) student(s).")
    }

    private func applyMerge(incoming: [StudentRosterEntry]) {
        let result = StudentRosterStore.upsert(incoming, into: entries)
        entries = result.merged
        tableView.reloadData()
        var message = "Added \(result.addedCount) new student(s)."
        if result.updatedCount > 0 {
            message += " Updated \(result.updatedCount) existing."
        }
        persistAndReport(message: message)
    }

    private func persistAndReport(message: String) {
        do {
            try StudentRosterStore.save(entries, to: storeURL)
            setStatus(message)
        } catch {
            setStatus("\(message) Could not save: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        do {
            entries = try StudentRosterStore.load(from: storeURL)
        } catch {
            entries = []
            setStatus("Could not load the saved roster: \(error.localizedDescription)")
        }
        tableView.reloadData()
    }

    private func setStatus(_ text: String) {
        statusLabel.maximumNumberOfLines = 4
        statusLabel.stringValue = text
    }
}
