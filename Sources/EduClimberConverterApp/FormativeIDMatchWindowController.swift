import AppKit
import UniformTypeIdentifiers

import EduClimberKit

/// Lets the user build up the persisted Formative ID -> WCSD email table by
/// hand: paste rows copied from Excel, or import a CSV. Stays open on its
/// own, independent of the main window -- not a sheet -- since the natural
/// workflow is "resolve a few ids whenever I come across them," not
/// something tied to any one conversion.
final class FormativeIDMatchWindowController: NSWindowController, NSTableViewDataSource {
    private let storeURL: URL
    private var matches: [FormativeIDMatch] = []
    private let tableView = NSTableView()
    private let statusLabel = makeLabel("", secondary: true)
    private let pasteTextView = NSTextView()

    init(storeURL: URL = FormativeIDMatchStore.defaultStoreURL()) {
        self.storeURL = storeURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Formative ID Matches"
        window.minSize = NSSize(width: 480, height: 420)
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
            "When a Formative export has no email for a student, the converter checks here by "
            + "Formative ID before giving up. Add matches by pasting two columns copied from "
            + "Excel, or by importing a CSV with a Formative ID column and an Email column.",
            secondary: true)
        explanation.maximumNumberOfLines = 4

        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("formativeID"))
        idColumn.title = "Formative ID"
        idColumn.width = 240
        let emailColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("email"))
        emailColumn.title = "Email"
        emailColumn.width = 220
        tableView.addTableColumn(idColumn)
        tableView.addTableColumn(emailColumn)
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
        let matchesBox = makeBox(title: "Saved Matches", views: [tableScrollView, deleteButton])

        pasteTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        pasteTextView.isRichText = false
        let pasteScrollView = NSScrollView()
        pasteScrollView.documentView = pasteTextView
        pasteScrollView.hasVerticalScroller = true
        pasteScrollView.borderType = .bezelBorder
        pasteScrollView.translatesAutoresizingMaskIntoConstraints = false
        pasteTextView.autoresizingMask = [.width]

        let pasteHint = makeLabel(
            "One per line: Formative ID, then Email -- tab- or comma-separated (what Excel "
            + "puts on the clipboard when you copy two columns).", secondary: true)
        let addPastedButton = NSButton(
            title: "Add Pasted Rows", target: self, action: #selector(addPastedRows))
        addPastedButton.bezelStyle = .rounded
        let importButton = NSButton(
            title: "Import CSV…", target: self, action: #selector(importCSV))
        importButton.bezelStyle = .rounded
        let addButtonRow = NSStackView(views: [addPastedButton, importButton])
        addButtonRow.orientation = .horizontal
        addButtonRow.spacing = 8
        let addBox = makeBox(title: "Add Matches", views: [pasteHint, pasteScrollView, addButtonRow])

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
        matches.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard matches.indices.contains(row) else { return nil }
        switch tableColumn?.identifier.rawValue {
        case "formativeID": return matches[row].formativeID
        case "email": return matches[row].email
        default: return nil
        }
    }

    // MARK: - Actions

    @objc private func addPastedRows() {
        let incoming = FormativeIDMatchStore.parse(pastedText: pasteTextView.string)
        guard !incoming.isEmpty else {
            setStatus(
                "No valid rows found. Expected one per line: Formative ID, then Email, "
                + "separated by a tab or comma.")
            return
        }
        applyMerge(incoming: incoming)
        pasteTextView.string = ""
    }

    @objc private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import Formative ID Matches"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.importableTypes
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try FormativeIDMatchStore.loadMatches(fromFile: url)
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
        let names = ["csv", "tsv", "txt"]
        var types = names.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.commaSeparatedText, .plainText, .data])
        var seen = Set<String>()
        return types.filter { seen.insert($0.identifier).inserted }
    }()

    @objc private func deleteSelected() {
        let indices = tableView.selectedRowIndexes
        guard !indices.isEmpty else { return }
        // Removing from an array by index has to go highest-first, or each
        // removal shifts the indices still to come out from under it.
        for index in indices.sorted(by: >) {
            matches.remove(at: index)
        }
        tableView.reloadData()
        persistAndReport(message: "Deleted \(indices.count) match(es).")
    }

    private func applyMerge(incoming: [FormativeIDMatch]) {
        let result = FormativeIDMatchStore.merge(existing: matches, incoming: incoming)
        matches = result.merged
        tableView.reloadData()
        var message = "Added \(result.addedCount)."
        if result.duplicateCount > 0 {
            message += " \(result.duplicateCount) already saved (skipped)."
        }
        if !result.conflicts.isEmpty {
            let details = result.conflicts
                .map { "\($0.formativeID) → \($0.email)" }
                .joined(separator: ", ")
            message += " \(result.conflicts.count) conflict(s) kept the existing email -- edit "
                + "the row by hand if the new one is correct: \(details)"
        }
        persistAndReport(message: message)
    }

    private func persistAndReport(message: String) {
        do {
            try FormativeIDMatchStore.save(matches, to: storeURL)
            setStatus(message)
        } catch {
            setStatus("\(message) Could not save: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        do {
            matches = try FormativeIDMatchStore.load(from: storeURL)
        } catch {
            matches = []
            setStatus("Could not load saved matches: \(error.localizedDescription)")
        }
        tableView.reloadData()
    }

    private func setStatus(_ text: String) {
        statusLabel.maximumNumberOfLines = 4
        statusLabel.stringValue = text
    }
}
