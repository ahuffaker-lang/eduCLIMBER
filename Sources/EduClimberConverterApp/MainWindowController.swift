import AppKit
import UniformTypeIdentifiers

import EduClimberKit

/// The main window: choose a file, answer the batch prompts, convert, save.
///
/// Nothing here is specific to Running Records -- the assessment popup, the
/// prompt fields and the expected columns all come from the converter, so a
/// second assessment type appears in this window as soon as it is registered.
final class MainWindowController: NSWindowController, NSTextFieldDelegate {
    private let converters: [AssessmentConverter] = [
        RunningRecordsConverter(), HFWConverter(), EurekaMathConverter(), SkillAssessmentConverter(),
        FormativeConverter(),
    ]
    private var converter: AssessmentConverter { converters[assessmentPopUp.indexOfSelectedItem] }

    // Loaded file state. Column choices are remembered per file, so confirming a
    // misspelled header once covers re-converting after changing a prompt.
    private var sourceURL: URL?
    private var table: Table?
    private var mapping: ColumnMapping?
    private var result: ConversionResult?

    private let assessmentPopUp = NSPopUpButton()
    private let summaryLabel = makeLabel("", secondary: true)
    private let fileLabel = makeLabel("No file selected")
    private let matchColumnsButton = NSButton()
    private let promptStack = NSStackView()
    private let benchmarkLabel = makeLabel("", secondary: true)
    private let fileNameField = NSTextField()
    private let fileNamePreview = makeLabel("", secondary: true)
    private var promptControls: [String: NSControl] = [:]
    private let statusTextView = NSTextView()
    private let convertButton = NSButton()
    private let saveButton = NSButton()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "eduCLIMBER Assessment Converter"
        // A hard ceiling on width: the labels inside are told how wide they
        // may get before wrapping, but this is a backstop against the window
        // growing to fit them anyway rather than wrapping -- height is left
        // free, since a taller window for more Status text is genuinely useful.
        window.minSize = NSSize(width: 680, height: 480)
        window.maxSize = NSSize(width: 820, height: CGFloat.greatestFiniteMagnitude)
        window.center()
        window.setFrameAutosaveName("MainWindow")
        self.init(window: window)
        window.contentView = makeContentView()
        startNewFile()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let root = DropView()
        root.onDrop = { [weak self] url in self?.setSource(url) }
        root.registerForDraggedTypes([.fileURL])
        root.translatesAutoresizingMaskIntoConstraints = false

        assessmentPopUp.addItems(withTitles: converters.map(\.displayName))
        assessmentPopUp.target = self
        assessmentPopUp.action = #selector(assessmentChanged)
        summaryLabel.stringValue = converter.summary

        let assessmentBox = makeBox(title: "Assessment", views: [assessmentPopUp, summaryLabel])

        let chooseButton = NSButton(
            title: "Choose File…", target: self, action: #selector(chooseFile))
        chooseButton.bezelStyle = .rounded
        matchColumnsButton.title = "Match Columns…"
        matchColumnsButton.bezelStyle = .rounded
        matchColumnsButton.target = self
        matchColumnsButton.action = #selector(editColumns)
        matchColumnsButton.isEnabled = false

        let fileRow = NSStackView(views: [fileLabel, chooseButton, matchColumnsButton])
        fileRow.orientation = .horizontal
        fileRow.spacing = 8
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fileBox = makeBox(title: "Source File", views: [fileRow])

        promptStack.orientation = .vertical
        promptStack.alignment = .leading
        promptStack.spacing = 8
        benchmarkLabel.maximumNumberOfLines = 2
        benchmarkLabel.isHidden = true
        let promptBox = makeBox(title: "Batch Settings", views: [promptStack, benchmarkLabel])

        // Naming pattern. English and Spanish batches share a window and school
        // year, so the name has to carry whatever tells them apart.
        fileNameField.delegate = self
        fileNameField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        let resetButton = NSButton(
            title: "Use Default", target: self, action: #selector(resetFileNameTemplate))
        resetButton.bezelStyle = .rounded
        let patternRow = NSStackView(views: [fileNameField, resetButton])
        patternRow.orientation = .horizontal
        patternRow.spacing = 8
        let nameBox = makeBox(
            title: "Saved File Name", views: [patternRow, fileNamePreview])

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusTextView.isEditable = false
        statusTextView.isSelectable = true
        statusTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusTextView.autoresizingMask = [.width]
        scrollView.documentView = statusTextView
        let statusBox = makeBox(title: "Status", views: [scrollView])

        convertButton.title = "Convert"
        convertButton.bezelStyle = .rounded
        convertButton.keyEquivalent = "\r"
        convertButton.target = self
        convertButton.action = #selector(convert)
        saveButton.title = "Save CSV…"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(saveResult)
        saveButton.isEnabled = false

        let spacer = NSView()
        let buttonRow = NSStackView(views: [spacer, saveButton, convertButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let column = NSStackView(
            views: [assessmentBox, fileBox, promptBox, nameBox, statusBox, buttonRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        column.setHuggingPriority(.defaultLow, for: .horizontal)

        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            assessmentBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            fileBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            promptBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            nameBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            statusBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
        return root
    }

    private func makeBox(title: String, views: [NSView]) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titlePosition = .atTop
        box.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        for view in views {
            view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        return box
    }

    /// Build the batch-settings controls from whatever the converter declares.
    private func renderPrompts() {
        defer {
            loadFileNameTemplate()
            updateBenchmarkLine()
        }
        for view in promptStack.arrangedSubviews {
            promptStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        promptControls = [:]

        for prompt in converter.prompts {
            let label = makeLabel("\(prompt.label):")
            label.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let control: NSControl
            let displayView: NSView
            switch prompt.kind {
            case .choice(let options):
                let popUp = NSPopUpButton()
                popUp.addItems(withTitles: options)
                popUp.target = self
                popUp.action = #selector(promptChanged)
                control = popUp
                displayView = popUp
            case .text:
                let field = NSTextField()
                field.placeholderString = prompt.placeholder
                if let defaultValue = prompt.defaultValue { field.stringValue = defaultValue }
                field.delegate = self
                field.widthAnchor.constraint(equalToConstant: 160).isActive = true
                control = field
                displayView = field
            case .file:
                let field = NSTextField()
                field.placeholderString = "No file chosen"
                field.isEditable = false
                field.widthAnchor.constraint(equalToConstant: 220).isActive = true
                let chooseButton = NSButton(
                    title: "Choose File…", target: self, action: #selector(choosePromptFile))
                chooseButton.bezelStyle = .rounded
                chooseButton.identifier = NSUserInterfaceItemIdentifier(prompt.key)
                control = field
                let group = NSStackView(views: [field, chooseButton])
                group.orientation = .horizontal
                group.spacing = 6
                displayView = group
            }
            promptControls[prompt.key] = control

            let hint = makeLabel(prompt.help.isEmpty ? prompt.placeholder : prompt.help,
                                 secondary: true)
            // Narrower than makeLabel's default: this one sits in a row next
            // to the 150pt label and a control, not alone across the box.
            hint.preferredMaxLayoutWidth = 260
            let row = NSStackView(views: [label, displayView, hint])
            row.orientation = .horizontal
            row.spacing = 8
            promptStack.addArrangedSubview(row)
        }
    }

    /// The button beside a `.file` prompt's field; `identifier` carries which
    /// prompt it belongs to, since several such buttons can be on screen at
    /// once (not true today, but `renderPrompts` doesn't assume otherwise).
    @objc private func choosePromptFile(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue,
              let field = promptControls[key] as? NSTextField
        else { return }
        let panel = NSOpenPanel()
        panel.title = "Select File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.openableTypes
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        field.stringValue = url.path
        promptChanged()
    }

    /// The naming pattern is remembered per assessment, so it survives quitting.
    private var fileNameDefaultsKey: String { "fileNameTemplate.\(converter.key)" }

    private func loadFileNameTemplate() {
        let stored = UserDefaults.standard.string(forKey: fileNameDefaultsKey)
        let template = (stored?.isEmpty == false) ? stored! : converter.defaultFileNameTemplate
        fileNameField.stringValue = template
        updateFileNamePreview()
    }

    @objc private func resetFileNameTemplate() {
        UserDefaults.standard.removeObject(forKey: fileNameDefaultsKey)
        fileNameField.stringValue = converter.defaultFileNameTemplate
        updateFileNamePreview()
    }

    private func fileNameTemplate() -> String {
        let typed = fileNameField.stringValue.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? converter.defaultFileNameTemplate : typed
    }

    private func updateFileNamePreview() {
        UserDefaults.standard.set(fileNameField.stringValue, forKey: fileNameDefaultsKey)
        let tokens = FileNameTemplate.tokens(
            converter: converter, answers: answers(),
            sourceName: sourceURL?.lastPathComponent ?? "")
        let name = FileNameTemplate(fileNameTemplate()).render(tokens: tokens)
        let available = converter.fileNameTokens.map { "{\($0)}" }.joined(separator: " ")
        fileNamePreview.stringValue = "Saves as: \(name)\nAvailable: \(available)"
        fileNamePreview.maximumNumberOfLines = 2
    }

    private func answers() -> [String: String] {
        var values: [String: String] = [:]
        for prompt in converter.prompts {
            guard let control = promptControls[prompt.key] else { continue }
            if let popUp = control as? NSPopUpButton {
                values[prompt.key] = popUp.titleOfSelectedItem ?? ""
            } else if let field = control as? NSTextField {
                values[prompt.key] = field.stringValue.trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
        }
        return values
    }

    // MARK: - Actions

    @objc private func assessmentChanged() {
        summaryLabel.stringValue = converter.summary
        mapping = nil  // a different assessment expects different columns
        renderPrompts()
        invalidateResult()
    }

    @objc private func promptChanged() {
        invalidateResult()
        updateFileNamePreview()
        updateBenchmarkLine()
    }

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) !== fileNameField { invalidateResult() }
        updateFileNamePreview()
        updateBenchmarkLine()
    }

    /// Names the exact scoring table about to be applied -- e.g. which year's
    /// benchmark rubric -- so it is visible before Convert is ever clicked.
    /// Converters without such a table (the default) simply hide the line.
    private func updateBenchmarkLine() {
        guard let summary = converter.scoringTableSummary(for: answers()) else {
            benchmarkLabel.isHidden = true
            return
        }
        benchmarkLabel.isHidden = false
        if summary.isCarriedForward, let note = summary.carriedForwardNote {
            benchmarkLabel.stringValue = "\(summary.text)  (\(note))"
        } else {
            benchmarkLabel.stringValue = summary.text
        }
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Select the assessment export"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Deliberately permissive. Exports arrive named .xls when they are
        // really HTML or XML, and sometimes with no extension at all; a picker
        // that greys those out just blocks the user on a file the app can
        // actually read. Anything genuinely unreadable is reported on open.
        panel.allowedContentTypes = Self.openableTypes
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setSource(url)
    }

    /// Spreadsheet-ish types listed first, plus `data` so nothing is greyed out.
    private static let openableTypes: [UTType] = {
        let names = ["xlsx", "xlsm", "xls", "csv", "tsv", "txt", "xml", "html", "htm"]
        var types = names.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [.spreadsheet, .commaSeparatedText, .plainText, .data])
        var seen = Set<String>()
        return types.filter { seen.insert($0.identifier).inserted }
    }()

    /// Puts the window back to its just-launched state: no file, no batch
    /// answers, no result -- so starting the next conversion doesn't require
    /// quitting and reopening the app. The assessment choice resets too, since
    /// leaving it as-is while clearing everything else it governs (the prompts,
    /// the file-name template) would leave the window in a state init() never
    /// produces on its own.
    @objc func startNewFile() {
        sourceURL = nil
        table = nil
        mapping = nil
        fileLabel.stringValue = "No file selected"
        matchColumnsButton.isEnabled = false
        invalidateResult()
        assessmentPopUp.selectItem(at: 0)
        summaryLabel.stringValue = converter.summary
        renderPrompts()
        setStatus(
            "Choose a source export (.csv or .xlsx), fill in the batch settings, "
            + "then click Convert.\n\nYou can also drag a file onto this window.")
    }

    func setSource(_ url: URL) {
        sourceURL = url
        fileLabel.stringValue = url.path
        table = nil
        mapping = nil
        matchColumnsButton.isEnabled = false
        invalidateResult()
        setStatus("Selected: \(url.lastPathComponent)\nClick Convert when ready.")
    }

    /// Read the file, resolve any duplicate submissions, and auto-match
    /// columns. False if it could not be read, or duplicates were found but
    /// not resolved.
    @discardableResult
    private func load() -> Bool {
        if table != nil && mapping != nil { return true }
        guard let sourceURL else { return false }
        do {
            var loaded = try converter.loadSource(at: sourceURL)
            let groups = converter.duplicateGroups(in: loaded)
            if !groups.isEmpty {
                guard let window, let selections = DuplicatePickerSheet.run(
                    over: window, table: loaded, groups: groups,
                    displayColumns: converter.duplicatePickerColumns, converter: converter)
                else {
                    setStatus("Conversion cancelled — duplicate submissions were not resolved.")
                    return false
                }
                loaded = Pipeline.resolvingDuplicates(in: loaded, groups: groups, selections: selections)
            }
            table = loaded
            mapping = Pipeline.matchColumns(converter: converter, table: loaded)
            matchColumnsButton.isEnabled = true
            return true
        } catch {
            let message = error.localizedDescription
            setStatus("Could not read this file.\n\n\(message)")
            showAlert(message, style: .warning)
            return false
        }
    }

    /// Let the user review or fix which file column feeds each expected column.
    @objc @discardableResult private func editColumns() -> Bool {
        guard sourceURL != nil, load(), let current = mapping, let window else { return false }
        var updated = current
        let accepted = ColumnMatchSheet.run(
            over: window, mapping: &updated, converter: converter,
            fileName: sourceURL?.lastPathComponent ?? "")
        if accepted {
            mapping = updated
            invalidateResult()
            let lines = updated.matches.map { "  " + $0.describe }.joined(separator: "\n")
            setStatus("Column matching set:\n\(lines)\n\nClick Convert when ready.")
        }
        return accepted
    }

    @objc private func convert() {
        guard sourceURL != nil else {
            showAlert("Choose a source file first.", style: .informational)
            return
        }
        let answers = answers()
        let problems = Pipeline.validateAnswers(converter: converter, answers: answers)
        guard problems.isEmpty else {
            showAlert(problems.joined(separator: "\n"), style: .warning)
            return
        }

        // A dated scoring table carried forward for a later year than it was
        // built for is a real judgment call -- confirm rather than apply it
        // silently, even though the persistent Benchmark line already shows it.
        if let summary = converter.scoringTableSummary(for: answers), summary.isCarriedForward {
            let note = summary.carriedForwardNote.map { " (\($0))" } ?? ""
            guard confirm(
                "Using an Older Benchmark Table",
                "\(summary.text)\(note). It will still be used for this batch. "
                + "Continue, or cancel to update the table first.")
            else {
                setStatus("Conversion cancelled.")
                return
            }
        }

        invalidateResult()
        guard load(), let table, var mapping else { return }

        // A misspelled or renamed header, or a missing name column, is a question
        // rather than a failure: ask which column to use, pre-selecting the
        // closest header in the file.
        if mapping.needsConfirmation || !converter.problems(for: mapping).isEmpty {
            guard editColumns(), let confirmed = self.mapping else {
                let pending = (mapping.unsettled.map { "  " + $0.column.label }
                    + converter.problems(for: mapping).map { "  " + $0 })
                    .joined(separator: "\n")
                setStatus(
                    "Conversion cancelled — this still needs to be sorted out:\n"
                    + pending + "\n\nClick 'Match Columns…' to pick the columns.")
                return
            }
            mapping = confirmed
        }

        do {
            let converted = try Pipeline.convert(
                converter: converter, table: table, answers: answers, mapping: mapping)
            let name = sourceURL?.lastPathComponent ?? "this file"
            if !converted.errors.isEmpty || !converted.notices.isEmpty {
                // Blank and half-filled rows are normal in a real export, and a
                // benchmark disagreement is worth a look even when nothing blocks
                // the export -- so the review window opens for either case, not
                // just when something has to be skipped.
                setStatus(
                    "\(converted.rows.count) row(s) ready, "
                    + "\(converted.skippedRowCount) row(s) with problems, "
                    + "\(converted.noticeIssues.count) row(s) with benchmark notices "
                    + "in \(name):\n\n" + converted.fullReport())
                guard let window else { return }
                let decision = ReviewIssuesSheet.run(
                    over: window, result: converted, fileName: name)
                guard decision == .skipAndContinue, converted.hasUsableRows else {
                    setStatus(
                        "Conversion cancelled — nothing was exported.\n"
                        + "\(converted.skippedRowCount) row(s) need fixing in \(name):\n\n"
                        + converted.fullReport())
                    return
                }
            }
            result = converted
            saveButton.isEnabled = true
            let skippedNote = converted.skippedRowCount == 0
                ? ""
                : " (\(converted.skippedRowCount) row(s) skipped)"
            setStatus(
                "Ready: \(converted.rows.count) student row(s) converted from "
                + "\(name)\(skippedNote).")
            saveResult()
        } catch {
            setStatus("Could not convert this file.\n\n\(error.localizedDescription)")
            showAlert(error.localizedDescription, style: .warning)
        }
    }

    @objc private func saveResult() {
        guard let result else { return }
        let suggested = Pipeline.suggestedOutputURL(
            converter: converter, sourceURL: sourceURL, answers: answers(),
            template: fileNameTemplate())

        let panel = NSSavePanel()
        panel.title = "Save eduCLIMBER CSV"
        panel.nameFieldStringValue = suggested.lastPathComponent
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.allowedFileTypes = ["csv"]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try Pipeline.save(result: result, to: url)
            var message = "Converted \(result.rows.count) students — saved to\n\(url.path)"
            if result.skippedRowCount > 0 {
                message += "\n\n\(result.skippedRowCount) row(s) with problems were skipped "
                    + "and are not in the file."
            }
            if let followUp = result.followUpReport, !followUp.rows.isEmpty {
                let followUpURL = Pipeline.followUpReportURL(for: followUp, besideMain: url)
                try Pipeline.saveFollowUpReport(followUp, to: followUpURL)
                message += "\n\n\(followUp.rows.count) \(followUp.title.lowercased()) — see "
                    + followUpURL.lastPathComponent
            }
            setStatus(message)
            showAlert(message, style: .informational)
        } catch {
            showAlert("Could not save the file:\n\(error.localizedDescription)", style: .warning)
        }
    }

    // MARK: - Helpers

    private func invalidateResult() {
        result = nil
        saveButton.isEnabled = false
    }

    private func setStatus(_ text: String) {
        statusTextView.string = text
    }

    /// A synchronous Continue/Cancel prompt, for a decision that has to gate what
    /// happens next -- unlike `showAlert`, which just informs.
    private func confirm(_ title: String, _ message: String, continueTitle: String = "Continue") -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: continueTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showAlert(_ message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = "eduCLIMBER Assessment Converter"
        alert.informativeText = message
        alert.alertStyle = style
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}

func makeLabel(_ text: String, secondary: Bool = false) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 3
    // Auto Layout's intrinsic content size ignores lineBreakMode/
    // maximumNumberOfLines unless the field is also told how wide it's
    // allowed to get -- without this, a long converter summary doesn't wrap,
    // it just reports its full unwrapped width and the window grows to fit.
    // A call site with a narrower (or wider) home overrides this afterward.
    label.preferredMaxLayoutWidth = 640
    if secondary {
        label.textColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    }
    return label
}

/// The window's content view, so a file can be dropped anywhere on it. The
/// view itself must register for the drag types it accepts -- registering the
/// window instead (as this used to) leaves draggingEntered/performDragOperation
/// here dead code, since AppKit only calls them on a view that registered.
final class DropView: NSView {
    var onDrop: ((URL) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedURL(sender) else { return false }
        onDrop?(url)
        return true
    }

    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil) as? [URL] else { return nil }
        return urls.first
    }
}
