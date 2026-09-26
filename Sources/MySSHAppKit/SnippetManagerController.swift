import AppKit

struct SavedSnippet: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var shortcut: Int?

    init(id: UUID = UUID(), name: String, command: String, shortcut: Int? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.shortcut = shortcut
    }
}

enum SnippetStore {
    private static let key = "savedSnippets.v2"
    private static let legacyKey = "savedSnippets"

    static func load() -> [SavedSnippet] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key),
           let snippets = try? JSONDecoder().decode([SavedSnippet].self, from: data) {
            return snippets
        }
        let legacy = defaults.stringArray(forKey: legacyKey) ?? []
        let migrated = legacy.enumerated().map { index, command in
            SavedSnippet(name: suggestedName(for: command, fallback: index + 1), command: command)
        }
        save(migrated)
        return migrated
    }

    static func save(_ snippets: [SavedSnippet]) {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func suggestedName(for command: String, fallback: Int) -> String {
        let line = command.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Snippet \(fallback)"
        return line.count > 38 ? String(line.prefix(35)) + "…" : line
    }
}

@MainActor
final class SnippetManagerController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSend: ((String) -> Void)?

    private var snippets: [SavedSnippet]
    private let tableView = NSTableView()
    private let nameField = NSTextField()
    private let commandView = NSTextView()
    private let shortcutPopup = NSPopUpButton()
    private let deleteButton = NSButton(title: "Elimina", target: nil, action: nil)
    private let saveButton = NSButton(title: "Salva modifiche", target: nil, action: nil)
    private let sendButton = NSButton(title: "Invia", target: nil, action: nil)

    init(snippets: [SavedSnippet] = SnippetStore.load()) {
        self.snippets = snippets
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 480))

        let title = NSTextField(labelWithString: "Snippet")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet"))
        column.title = "Snippet salvati"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsEmptySelection = true
        tableView.target = self
        tableView.doubleAction = #selector(sendSelected)

        let listScroll = NSScrollView()
        listScroll.documentView = tableView
        listScroll.hasVerticalScroller = true
        listScroll.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: "Nuovo", target: self, action: #selector(addSnippet))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSnippet)
        let listButtons = NSStackView(views: [addButton, deleteButton])
        listButtons.orientation = .horizontal
        listButtons.spacing = 8
        listButtons.translatesAutoresizingMaskIntoConstraints = false

        nameField.placeholderString = "Nome snippet"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        shortcutPopup.addItems(withTitles: ["Nessuna scorciatoia"] + (1...9).map { "⌘⇧\($0)" })
        shortcutPopup.target = self
        shortcutPopup.action = #selector(shortcutChanged)
        shortcutPopup.translatesAutoresizingMaskIntoConstraints = false

        commandView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        commandView.isRichText = false
        commandView.isAutomaticQuoteSubstitutionEnabled = false
        commandView.isAutomaticDashSubstitutionEnabled = false
        let commandScroll = NSScrollView()
        commandScroll.documentView = commandView
        commandScroll.hasVerticalScroller = true
        commandScroll.borderType = .bezelBorder
        commandScroll.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "Nome")
        let shortcutLabel = NSTextField(labelWithString: "Scorciatoia")
        let commandLabel = NSTextField(labelWithString: "Comando")
        [nameLabel, shortcutLabel, commandLabel].forEach { $0.font = .systemFont(ofSize: 12, weight: .medium); $0.translatesAutoresizingMaskIntoConstraints = false }

        let closeButton = NSButton(title: "Chiudi", target: self, action: #selector(closeManager))
        saveButton.target = self
        saveButton.action = #selector(saveChanges)
        sendButton.target = self
        sendButton.action = #selector(sendSelected)
        sendButton.keyEquivalent = "\r"
        let actionButtons = NSStackView(views: [closeButton, saveButton, sendButton])
        actionButtons.orientation = .horizontal
        actionButtons.spacing = 8
        actionButtons.translatesAutoresizingMaskIntoConstraints = false

        [title, listScroll, listButtons, nameLabel, nameField, shortcutLabel, shortcutPopup, commandLabel, commandScroll, actionButtons].forEach(view.addSubview)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            listScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            listScroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            listScroll.bottomAnchor.constraint(equalTo: listButtons.topAnchor, constant: -10),
            listScroll.widthAnchor.constraint(equalToConstant: 250),
            listButtons.leadingAnchor.constraint(equalTo: listScroll.leadingAnchor),
            listButtons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            nameLabel.leadingAnchor.constraint(equalTo: listScroll.trailingAnchor, constant: 24),
            nameLabel.topAnchor.constraint(equalTo: listScroll.topAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            shortcutLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            shortcutLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            shortcutPopup.leadingAnchor.constraint(equalTo: shortcutLabel.leadingAnchor),
            shortcutPopup.topAnchor.constraint(equalTo: shortcutLabel.bottomAnchor, constant: 5),
            shortcutPopup.widthAnchor.constraint(equalToConstant: 180),
            commandLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            commandLabel.topAnchor.constraint(equalTo: shortcutPopup.bottomAnchor, constant: 14),
            commandScroll.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            commandScroll.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            commandScroll.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 5),
            commandScroll.bottomAnchor.constraint(equalTo: actionButtons.topAnchor, constant: -14),
            actionButtons.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            actionButtons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])

        if snippets.isEmpty {
            setEditorEnabled(false)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            loadSelection()
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { snippets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let snippet = snippets[row]
        let cell = NSTableCellView()
        let name = NSTextField(labelWithString: snippet.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let preview = NSTextField(labelWithString: snippet.command.replacingOccurrences(of: "\n", with: " "))
        preview.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        preview.textColor = .secondaryLabelColor
        preview.lineBreakMode = .byTruncatingTail
        let shortcut = NSTextField(labelWithString: snippet.shortcut.map { "⌘⇧\($0)" } ?? "")
        shortcut.textColor = .systemBlue
        [name, preview, shortcut].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
            name.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -6),
            shortcut.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            shortcut.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            preview.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            preview.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { loadSelection() }

    @objc private func addSnippet() {
        saveCurrentIfPossible()
        snippets.append(SavedSnippet(name: "Nuovo snippet", command: ""))
        SnippetStore.save(snippets)
        tableView.reloadData()
        let row = snippets.count - 1
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        loadSelection()
        view.window?.makeFirstResponder(nameField)
    }

    @objc private func deleteSnippet() {
        guard snippets.indices.contains(tableView.selectedRow) else { return }
        snippets.remove(at: tableView.selectedRow)
        SnippetStore.save(snippets)
        tableView.reloadData()
        if snippets.isEmpty {
            tableView.deselectAll(nil)
            setEditorEnabled(false)
            nameField.stringValue = ""
            commandView.string = ""
        } else {
            let row = min(tableView.selectedRow, snippets.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: max(0, row)), byExtendingSelection: false)
            loadSelection()
        }
    }

    @objc private func saveChanges() {
        guard saveCurrentIfPossible() else { return }
        tableView.reloadData()
    }

    @objc private func shortcutChanged() {
        guard saveCurrentIfPossible() else { return }
        tableView.reloadData()
    }

    @objc private func sendSelected() {
        guard saveCurrentIfPossible(), snippets.indices.contains(tableView.selectedRow) else { return }
        let command = snippets[tableView.selectedRow].command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        onSend?(command)
        dismiss(nil)
    }

    @objc private func closeManager() {
        saveCurrentIfPossible()
        dismiss(nil)
    }

    private func loadSelection() {
        guard snippets.indices.contains(tableView.selectedRow) else { return setEditorEnabled(false) }
        let snippet = snippets[tableView.selectedRow]
        nameField.stringValue = snippet.name
        commandView.string = snippet.command
        shortcutPopup.selectItem(at: snippet.shortcut ?? 0)
        setEditorEnabled(true)
    }

    @discardableResult
    private func saveCurrentIfPossible() -> Bool {
        let row = tableView.selectedRow
        guard snippets.indices.contains(row) else { return false }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = commandView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { NSSound.beep(); return false }
        let shortcut = shortcutPopup.indexOfSelectedItem == 0 ? nil : shortcutPopup.indexOfSelectedItem
        if let shortcut {
            for index in snippets.indices where index != row && snippets[index].shortcut == shortcut {
                snippets[index].shortcut = nil
            }
        }
        snippets[row].name = name
        snippets[row].command = command
        snippets[row].shortcut = shortcut
        SnippetStore.save(snippets)
        return true
    }

    private func setEditorEnabled(_ enabled: Bool) {
        nameField.isEnabled = enabled
        shortcutPopup.isEnabled = enabled
        commandView.isEditable = enabled
        deleteButton.isEnabled = enabled
        saveButton.isEnabled = enabled
        sendButton.isEnabled = enabled
    }
}
