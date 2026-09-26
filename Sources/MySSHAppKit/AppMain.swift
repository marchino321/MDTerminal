import AppKit
@preconcurrency import SwiftTerm
import MySSHCore
import UniformTypeIdentifiers

private enum MDTheme {
    static let background = NSColor(srgbRed: 0.055, green: 0.071, blue: 0.125, alpha: 1)
    static let sidebar = NSColor(srgbRed: 0.075, green: 0.094, blue: 0.160, alpha: 1)
    static let surface = NSColor(srgbRed: 0.125, green: 0.151, blue: 0.245, alpha: 1)
    static let surfaceRaised = NSColor(srgbRed: 0.157, green: 0.184, blue: 0.286, alpha: 1)
    static let border = NSColor(srgbRed: 0.205, green: 0.235, blue: 0.350, alpha: 1)
    static let text = NSColor(srgbRed: 0.925, green: 0.941, blue: 0.980, alpha: 1)
    static let mutedText = NSColor(srgbRed: 0.570, green: 0.610, blue: 0.710, alpha: 1)
    static let cyan = NSColor(srgbRed: 0.055, green: 0.790, blue: 0.870, alpha: 1)
    static let pink = NSColor(srgbRed: 0.965, green: 0.160, blue: 0.365, alpha: 1)
    static let green = NSColor(srgbRed: 0.190, green: 0.820, blue: 0.410, alpha: 1)
    static let orange = NSColor(srgbRed: 0.965, green: 0.620, blue: 0.145, alpha: 1)

    static let terminalPalette: [Color] = [
        background, pink, green, orange,
        NSColor(srgbRed: 0.300, green: 0.520, blue: 0.980, alpha: 1),
        NSColor(srgbRed: 0.720, green: 0.350, blue: 0.950, alpha: 1),
        cyan, text,
        mutedText, NSColor(srgbRed: 1.000, green: 0.320, blue: 0.470, alpha: 1),
        NSColor(srgbRed: 0.330, green: 0.900, blue: 0.530, alpha: 1),
        NSColor(srgbRed: 1.000, green: 0.760, blue: 0.300, alpha: 1),
        NSColor(srgbRed: 0.430, green: 0.650, blue: 1.000, alpha: 1),
        NSColor(srgbRed: 0.850, green: 0.500, blue: 1.000, alpha: 1),
        NSColor(srgbRed: 0.250, green: 0.900, blue: 0.940, alpha: 1),
        .white
    ].map(Color.init(nsColor:))
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var controller: MainViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        configureMainMenu()
        controller = MainViewController()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MD Terminal"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = MDTheme.sidebar
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 1_000, height: 650)
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setFrame(visibleFrame, display: false)
        } else {
            window.center()
        }
        window.contentViewController = controller
        window.toolbar = controller.makeToolbar()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Esci da MD Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Modifica")
        editMenu.addItem(withTitle: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

@main
struct MySSHMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class MainViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate, NSToolbarDelegate {
    private let service = HostService(persistence: AppDataStore(), secrets: KeychainStore())
    private let commandBuilder = OpenSSHCommandBuilder()
    private let localHost = MySSHCore.Host(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Terminale locale",
        hostname: "Questo Mac",
        username: NSUserName(),
        group: "Locale",
        symbolName: "desktopcomputer",
        isFavorite: true
    )
    private var hosts: [MySSHCore.Host] = []
    private var filteredHosts: [MySSHCore.Host] = []
    private var sessions: [TerminalSession] = []
    private var auxiliaryWindows: [NSWindowController] = []
    private var selectedSessionIndex: Int?
    private var editorController: HostEditorController?
    private var snippetShortcutMonitor: Any?

    private let mainSplitView = NSSplitView()
    private let sidebarPanel = NSView()
    private let detailPanel = NSView()
    private let editorPanel = NSVisualEffectView()
    private let collectionView = NSCollectionView()
    private let searchField = NSSearchField()
    private let terminalContainer = NSView()
    private let emptyLabel = NSTextField(labelWithString: "Seleziona un host e premi Connetti")
    private let tabControl = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "Pronto")
    private let pageTitle = NSTextField(labelWithString: "Hosts")
    private let groupTitle = NSTextField(labelWithString: "Gruppi")
    private let groupStack = NSStackView()
    private let terminalPadding = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    private var selectedGroup: String?

    override func loadView() {
        view = NSView()
        configureLayout()
        installSnippetShortcutMonitor()
        Task { await loadHosts() }
    }

    private var selectedHost: MySSHCore.Host? {
        guard let index = collectionView.selectionIndexPaths.first?.item,
              filteredHosts.indices.contains(index) else { return nil }
        return filteredHosts[index]
    }

    private func isLocalHost(_ host: MySSHCore.Host) -> Bool { host.id == localHost.id }

    private func configureLayout() {
        view.wantsLayer = true
        view.layer?.backgroundColor = MDTheme.background.cgColor
        mainSplitView.isVertical = true
        mainSplitView.dividerStyle = .thin
        mainSplitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainSplitView)
        NSLayoutConstraint.activate([
            mainSplitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainSplitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainSplitView.topAnchor.constraint(equalTo: view.topAnchor),
            mainSplitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        sidebarPanel.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.widthAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true
        sidebarPanel.wantsLayer = true
        sidebarPanel.layer?.backgroundColor = MDTheme.background.cgColor

        pageTitle.font = .systemFont(ofSize: 22, weight: .bold)
        pageTitle.textColor = MDTheme.text
        pageTitle.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(pageTitle)

        groupTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        groupTitle.textColor = MDTheme.mutedText
        groupTitle.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(groupTitle)

        groupStack.orientation = .horizontal
        groupStack.alignment = .centerY
        groupStack.spacing = 8
        groupStack.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(groupStack)

        searchField.placeholderString = "Cerca server"
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.textColor = MDTheme.text
        (searchField.cell as? NSSearchFieldCell)?.backgroundColor = MDTheme.surface
        searchField.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(searchField)

        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NSSize(width: 300, height: 78)
        flowLayout.sectionInset = NSEdgeInsets(top: 12, left: 18, bottom: 16, right: 18)
        flowLayout.minimumInteritemSpacing = 12
        flowLayout.minimumLineSpacing = 12
        collectionView.collectionViewLayout = flowLayout
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(HostCollectionItem.self, forItemWithIdentifier: .hostCard)
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(connectSelected))
        doubleClick.numberOfClicksRequired = 2
        collectionView.addGestureRecognizer(doubleClick)

        let scroll = NSScrollView()
        scroll.documentView = collectionView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(scroll)

        let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Nuovo host")!, target: self, action: #selector(addHost))
        addButton.bezelStyle = .inline
        addButton.contentTintColor = MDTheme.cyan
        addButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.addSubview(addButton)

        NSLayoutConstraint.activate([
            pageTitle.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 18),
            pageTitle.topAnchor.constraint(equalTo: sidebarPanel.topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: pageTitle.trailingAnchor, constant: 24),
            searchField.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: -18),
            searchField.centerYAnchor.constraint(equalTo: pageTitle.centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            groupTitle.leadingAnchor.constraint(equalTo: pageTitle.leadingAnchor),
            groupTitle.topAnchor.constraint(equalTo: pageTitle.bottomAnchor, constant: 20),
            groupStack.leadingAnchor.constraint(equalTo: groupTitle.trailingAnchor, constant: 14),
            groupStack.centerYAnchor.constraint(equalTo: groupTitle.centerYAnchor),
            groupStack.trailingAnchor.constraint(lessThanOrEqualTo: sidebarPanel.trailingAnchor, constant: -18),
            scroll.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: groupTitle.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -6),
            addButton.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 10),
            addButton.bottomAnchor.constraint(equalTo: sidebarPanel.bottomAnchor, constant: -8)
        ])

        let topBar = NSVisualEffectView()
        topBar.material = .sidebar
        topBar.blendingMode = .withinWindow
        topBar.translatesAutoresizingMaskIntoConstraints = false
        tabControl.target = self
        tabControl.action = #selector(selectTab)
        tabControl.segmentStyle = .automatic
        tabControl.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = MDTheme.mutedText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(tabControl)
        topBar.addSubview(statusLabel)

        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.wantsLayer = true
        terminalContainer.layer?.backgroundColor = MDTheme.background.cgColor
        detailPanel.addSubview(topBar)
        detailPanel.addSubview(terminalContainer)
        emptyLabel.font = .systemFont(ofSize: 20, weight: .medium)
        emptyLabel.textColor = MDTheme.mutedText
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: detailPanel.topAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),
            tabControl.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            tabControl.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            tabControl.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -12),
            statusLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            terminalContainer.leadingAnchor.constraint(equalTo: detailPanel.leadingAnchor),
            terminalContainer.trailingAnchor.constraint(equalTo: detailPanel.trailingAnchor),
            terminalContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            terminalContainer.bottomAnchor.constraint(equalTo: detailPanel.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: terminalContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: terminalContainer.centerYAnchor)
        ])

        mainSplitView.addArrangedSubview(sidebarPanel)
        mainSplitView.addArrangedSubview(detailPanel)
        detailPanel.isHidden = true

        editorPanel.material = .sidebar
        editorPanel.blendingMode = .withinWindow
        editorPanel.state = .active
        editorPanel.isHidden = true
        editorPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editorPanel)
        NSLayoutConstraint.activate([
            editorPanel.topAnchor.constraint(equalTo: view.topAnchor),
            editorPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            editorPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorPanel.widthAnchor.constraint(equalToConstant: 480)
        ])
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MySSH.Toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.add, .importConfig, .portableImport, .portableExport, .edit, .delete, .connect, .disconnect, .newTab, .sftp, .snippets, .forward, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.add, .importConfig, .portableImport, .portableExport, .edit, .delete, .flexibleSpace, .connect, .disconnect, .newTab, .sftp, .snippets, .forward]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let definitions: [NSToolbarItem.Identifier: (String, String, Selector)] = [
            .add: ("Nuovo", "plus", #selector(primaryAddAction)),
            .importConfig: ("Importa", "square.and.arrow.down", #selector(importSSHConfig)),
            .portableImport: ("Importa archivio", "arrow.down.doc", #selector(importPortableArchive)),
            .portableExport: ("Esporta per iPad", "arrow.up.doc", #selector(exportPortableArchive)),
            .edit: ("Modifica", "pencil", #selector(editHost)),
            .delete: ("Elimina", "trash", #selector(deleteHost)),
            .connect: ("Connetti", "bolt.fill", #selector(connectSelected)),
            .disconnect: ("Chiudi tab", "xmark", #selector(closeSession)),
            .newTab: ("Nuovo tab", "plus.square.on.square", #selector(chooseHostForNewSession)),
            .sftp: ("SFTP", "folder", #selector(openSFTP)),
            .snippets: ("Snippet", "chevron.left.forwardslash.chevron.right", #selector(showSnippets)),
            .forward: ("Forwarding", "arrow.triangle.branch", #selector(openForward))
        ]
        guard let definition = definitions[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = definition.0
        item.image = NSImage(systemSymbolName: definition.1, accessibilityDescription: definition.0)
        item.target = self
        item.action = definition.2
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredHosts.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .hostCard, for: indexPath)
        (item as? HostCollectionItem)?.configure(with: filteredHosts[indexPath.item])
        return item
    }

    func controlTextDidChange(_ obj: Notification) { applyFilter() }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let availableHosts = [localHost] + hosts
        let groupFiltered = availableHosts.filter { host in
            guard let selectedGroup else { return true }
            return (host.group ?? "Senza gruppo") == selectedGroup
        }
        filteredHosts = query.isEmpty ? groupFiltered : groupFiltered.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.hostname.localizedCaseInsensitiveContains(query)
                || ($0.group?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        filteredHosts.sort {
            if isLocalHost($0) != isLocalHost($1) { return isLocalHost($0) }
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        collectionView.reloadData()
        rebuildGroupFilters(from: availableHosts)
    }

    private func rebuildGroupFilters(from hosts: [MySSHCore.Host]) {
        groupStack.arrangedSubviews.forEach { view in
            groupStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let groups = Set(hosts.map { $0.group ?? "Senza gruppo" }).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        for group in [nil] + groups.map(Optional.some) {
            let title = group ?? "Tutti"
            let count = group.map { selected in hosts.filter { ($0.group ?? "Senza gruppo") == selected }.count } ?? hosts.count
            let button = NSButton(title: "\(title)  \(count)", target: self, action: #selector(selectGroup(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(group ?? "__all__")
            button.bezelStyle = .recessed
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: selectedGroup == group ? .semibold : .regular)
            button.contentTintColor = selectedGroup == group ? MDTheme.cyan : MDTheme.mutedText
            groupStack.addArrangedSubview(button)
        }
    }

    @objc private func selectGroup(_ sender: NSButton) {
        let value = sender.identifier?.rawValue
        selectedGroup = value == "__all__" ? nil : value
        applyFilter()
    }

    private func loadHosts() async {
        do { hosts = try await service.loadHosts(); applyFilter() }
        catch { showError(error) }
    }

    @objc private func primaryAddAction() {
        if sessions.isEmpty {
            addHost()
        } else {
            chooseHostForNewSession()
        }
    }

    @objc private func addHost() { presentEditor(host: .empty) }
    @objc private func importSSHConfig() {
        let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        do {
            let contents = try String(contentsOf: configURL, encoding: .utf8)
            let imported = SSHConfigParser().parse(contents)
            guard !imported.isEmpty else { return showErrorMessage("Nessun host importabile trovato in ~/.ssh/config.") }
            Task {
                do {
                    var current = hosts
                    var importedCount = 0
                    for host in imported where !current.contains(where: { $0.name == host.name }) {
                        current = try await service.save(host: host, password: nil, passphrase: nil)
                        importedCount += 1
                    }
                    hosts = current; applyFilter()
                    statusLabel.stringValue = "Importati \(importedCount) host"
                } catch { showError(error) }
            }
        } catch { showErrorMessage("Impossibile leggere ~/.ssh/config: \(error.localizedDescription)") }
    }

    @objc private func exportPortableArchive() {
        guard let passphrase = requestArchivePassphrase(confirm: true) else { return }
        let panel = NSSavePanel()
        panel.title = "Esporta host e password"
        panel.nameFieldStringValue = "MDTerminal-backup.mdterminal.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                statusLabel.stringValue = "Cifratura archivio…"
                let archive = try await service.exportPortableArchive(passphrase: passphrase)
                try archive.write(to: url, options: [.atomic, .completeFileProtection])
                statusLabel.stringValue = "Archivio esportato"
            } catch { showError(error) }
        }
    }

    @objc private func importPortableArchive() {
        let panel = NSOpenPanel()
        panel.title = "Importa host e password"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let passphrase = requestArchivePassphrase(confirm: false) else { return }
        Task {
            do {
                statusLabel.stringValue = "Decifratura archivio…"
                let archive = try Data(contentsOf: url)
                hosts = try await service.importPortableArchive(archive, passphrase: passphrase)
                applyFilter()
                statusLabel.stringValue = "Importati \(hosts.count) host"
            } catch { showError(error) }
        }
    }

    private func requestArchivePassphrase(confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = confirm ? "Proteggi l'archivio" : "Sblocca l'archivio"
        alert.informativeText = confirm
            ? "Questa password sarà necessaria su iPad. Non viene salvata."
            : "Inserisci la password usata durante l'esportazione."
        let height: CGFloat = confirm ? 62 : 28
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: height))
        let first = NSSecureTextField(frame: NSRect(x: 0, y: confirm ? 34 : 0, width: 360, height: 26))
        first.placeholderString = "Password archivio"
        accessory.addSubview(first)
        var confirmation: NSSecureTextField?
        if confirm {
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
            second.placeholderString = "Ripeti password"
            accessory.addSubview(second)
            confirmation = second
        }
        alert.accessoryView = accessory
        alert.addButton(withTitle: confirm ? "Continua" : "Importa")
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard !first.stringValue.isEmpty else { showErrorMessage("La password non può essere vuota."); return nil }
        if let confirmation, first.stringValue != confirmation.stringValue {
            showErrorMessage("Le due password non coincidono.")
            return nil
        }
        return first.stringValue
    }

    @objc private func editHost() {
        guard let selectedHost else { return }
        guard !isLocalHost(selectedHost) else { return showErrorMessage("Il Terminale locale è integrato e non richiede configurazione.") }
        presentEditor(host: selectedHost)
    }

    private func presentEditor(host: MySSHCore.Host) {
        Task {
            do {
                let credential = try await service.credential(for: host)
                showEditor(host: host, credential: credential)
            } catch {
                showError(error)
            }
        }
    }

    private func showEditor(host: MySSHCore.Host, credential: String?) {
        hideEditor()
        let groups = Array(Set(hosts.compactMap { $0.group?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let tags = Array(Set(hosts.flatMap(\.tags).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let editor = HostEditorController(host: host, groups: groups, tagSuggestions: tags, credential: credential)
        editorController = editor
        addChild(editor)
        editorPanel.addSubview(editor.view)
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editor.view.leadingAnchor.constraint(equalTo: editorPanel.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: editorPanel.trailingAnchor),
            editor.view.topAnchor.constraint(equalTo: editorPanel.topAnchor),
            editor.view.bottomAnchor.constraint(equalTo: editorPanel.bottomAnchor)
        ])
        editorPanel.isHidden = false
        editor.onCancel = { [weak self] in self?.hideEditor() }
        editor.onSave = { [weak self] updated, password, passphrase in
            guard let self else { return }
            Task {
                do {
                    self.hosts = try await self.service.save(host: updated, password: password, passphrase: passphrase)
                    self.applyFilter()
                    self.hideEditor()
                } catch { self.showError(error) }
            }
        }
    }

    private func hideEditor() {
        editorController?.view.removeFromSuperview()
        editorController?.removeFromParent()
        editorController = nil
        editorPanel.isHidden = true
    }

    @objc private func deleteHost() {
        guard let host = selectedHost else { return }
        guard !isLocalHost(host) else { return showErrorMessage("Il Terminale locale è una funzione fissa dell'app.") }
        let alert = NSAlert()
        alert.messageText = "Eliminare \(host.name)?"
        alert.informativeText = "L'host e le relative credenziali nel Keychain verranno rimossi."
        alert.addButton(withTitle: "Elimina")
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do { hosts = try await service.delete(id: host.id); applyFilter() }
            catch { showError(error) }
        }
    }

    @objc private func connectSelected() { guard let host = selectedHost else { return }; openSession(host: host, mode: .shell) }

    @objc private func chooseHostForNewSession() {
        let candidates = [localHost] + hosts.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let alert = NSAlert()
        alert.messageText = "Nuova sessione"
        alert.informativeText = "Scegli l'host da aprire in un nuovo tab."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 390, height: 28))
        popup.addItems(withTitles: candidates.map { host in
            isLocalHost(host)
                ? "Terminale locale — Questo Mac"
                : "\(host.name) — \(host.username)@\(host.hostname)"
        })
        alert.accessoryView = popup
        alert.addButton(withTitle: "Apri sessione")
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn,
              candidates.indices.contains(popup.indexOfSelectedItem) else { return }
        openSession(host: candidates[popup.indexOfSelectedItem], mode: .shell)
    }

    @objc private func openSFTP() {
        guard let host = selectedHost else { return }
        guard !isLocalHost(host) else { return showErrorMessage("SFTP è disponibile solo per le connessioni remote.") }
        let controller = SFTPViewController(host: host, askPassPath: askPassPath())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SFTP — \(host.name)"
        window.minSize = NSSize(width: 980, height: 520)
        window.contentViewController = controller
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setFrame(visibleFrame, display: false)
        } else {
            window.center()
        }
        let windowController = NSWindowController(window: window)
        auxiliaryWindows.removeAll { $0.window == nil }
        auxiliaryWindows.append(windowController)
        windowController.showWindow(nil)
    }

    private func openSession(host: MySSHCore.Host, mode: SSHLaunchMode) {
        do {
            let local = isLocalHost(host)
            let configuration: SSHLaunchConfiguration?
            if local {
                configuration = nil
            } else {
                configuration = try commandBuilder.make(host: host, mode: mode, askPassPath: askPassPath())
            }
            let terminal = LocalProcessTerminalView(
                frame: terminalFrame,
                font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                options: TerminalOptions(scrollback: 10_000)
            )
            terminal.autoresizingMask = [.width, .height]
            terminal.processDelegate = self
            try? terminal.setUseMetal(false)
            terminal.nativeBackgroundColor = MDTheme.background
            terminal.nativeForegroundColor = MDTheme.text
            terminal.caretColor = MDTheme.cyan
            terminal.caretTextColor = MDTheme.background
            terminal.selectedTextBackgroundColor = MDTheme.cyan.withAlphaComponent(0.28)
            terminal.selectedTextForegroundColor = MDTheme.text
            terminal.installColors(MDTheme.terminalPalette)
            let baseTitle = modeTitle(mode, host: host)
            let sameHostSessions = sessions.filter { $0.host.id == host.id }.count
            let title = sameHostSessions == 0 ? baseTitle : "\(baseTitle) \(sameHostSessions + 1)"
            let session = TerminalSession(id: UUID(), title: title, host: host, terminal: terminal)
            sessions.append(session)
            selectedSessionIndex = sessions.count - 1
            hideEditor()
            sidebarPanel.isHidden = true
            detailPanel.isHidden = false
            mainSplitView.adjustSubviews()
            rebuildTabs()
            showSelectedSession()
            if local {
                var environmentValues = ProcessInfo.processInfo.environment
                environmentValues["TERM"] = "xterm-256color"
                let shell = environmentValues["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
                let environment = environmentValues.map { "\($0.key)=\($0.value)" }
                statusLabel.stringValue = "Terminale locale"
                terminal.startProcess(
                    executable: shell,
                    args: ["-l"],
                    environment: environment,
                    currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
                )
            } else if let configuration {
                statusLabel.stringValue = "Connessione a \(host.hostname)…"
                terminal.startProcess(executable: configuration.executable, args: configuration.arguments, environment: configuration.environment)
            }
            view.window?.makeFirstResponder(terminal)
        } catch { showError(error) }
    }

    private func askPassPath() -> String? {
        let besideExecutable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MySSHAskPass").path
        if FileManager.default.isExecutableFile(atPath: besideExecutable) { return besideExecutable }
        let development = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("MySSHAskPass").path
        return development.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    private func modeTitle(_ mode: SSHLaunchMode, host: MySSHCore.Host) -> String {
        if case .sftp = mode { return "SFTP · \(host.name)" }
        return host.name
    }

    private func rebuildTabs() {
        tabControl.segmentCount = sessions.count
        for (index, session) in sessions.enumerated() { tabControl.setLabel(session.title, forSegment: index) }
        if let selectedSessionIndex, sessions.indices.contains(selectedSessionIndex) { tabControl.selectedSegment = selectedSessionIndex }
        tabControl.isHidden = sessions.isEmpty
    }

    @objc private func selectTab() {
        guard sessions.indices.contains(tabControl.selectedSegment) else { return }
        selectedSessionIndex = tabControl.selectedSegment
        showSelectedSession()
    }

    private func showSelectedSession() {
        terminalContainer.subviews.filter { $0 !== emptyLabel }.forEach { $0.removeFromSuperview() }
        guard let index = selectedSessionIndex, sessions.indices.contains(index) else {
            emptyLabel.isHidden = false
            statusLabel.stringValue = "Pronto"
            return
        }
        emptyLabel.isHidden = true
        let terminal = sessions[index].terminal
        terminal.frame = terminalFrame
        terminalContainer.addSubview(terminal)
        statusLabel.stringValue = sessions[index].isRunning ? "Connesso" : "Terminato"
        view.window?.makeFirstResponder(terminal)
    }

    private var terminalFrame: NSRect {
        NSRect(
            x: terminalPadding.left,
            y: terminalPadding.bottom,
            width: max(0, terminalContainer.bounds.width - terminalPadding.left - terminalPadding.right),
            height: max(0, terminalContainer.bounds.height - terminalPadding.top - terminalPadding.bottom)
        )
    }

    @objc private func closeSession() {
        guard let index = selectedSessionIndex, sessions.indices.contains(index) else { return }
        sessions[index].terminal.terminate()
        sessions.remove(at: index)
        selectedSessionIndex = sessions.isEmpty ? nil : min(index, sessions.count - 1)
        sidebarPanel.isHidden = !sessions.isEmpty
        detailPanel.isHidden = sessions.isEmpty
        mainSplitView.adjustSubviews()
        rebuildTabs()
        showSelectedSession()
    }

    @objc private func showSnippets() {
        guard selectedSessionIndex != nil else { return }
        let manager = SnippetManagerController()
        manager.onSend = { [weak self] command in self?.sendSnippetCommand(command) }
        presentAsSheet(manager)
    }

    private func installSnippetShortcutMonitor() {
        guard snippetShortcutMonitor == nil else { return }
        snippetShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleSnippetShortcut(event) else { return event }
            return nil
        }
    }

    private func handleSnippetShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), modifiers.contains(.shift),
              let shortcut = snippetShortcut(forKeyCode: event.keyCode),
              let snippet = SnippetStore.load().first(where: { $0.shortcut == shortcut }) else { return false }
        sendSnippetCommand(snippet.command)
        return true
    }

    private func snippetShortcut(forKeyCode keyCode: UInt16) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]
    }

    private func sendSnippetCommand(_ command: String) {
        guard let index = selectedSessionIndex, sessions.indices.contains(index) else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[index].terminal.process.send(data: ArraySlice(Array((trimmed + "\n").utf8)))
        statusLabel.stringValue = "Snippet inviato"
    }

    @objc private func openForward() {
        guard let host = selectedHost else { return }
        guard !isLocalHost(host) else { return showErrorMessage("Il port forwarding richiede una connessione SSH remota.") }
        let alert = NSAlert()
        alert.messageText = "Port forwarding"
        let type = NSPopUpButton(frame: NSRect(x: 0, y: 32, width: 320, height: 26))
        type.addItems(withTitles: ["Locale", "Remoto", "SOCKS dinamico"])
        let field = NSTextField(string: "8080:127.0.0.1:80")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 60)); accessory.addSubview(type); accessory.addSubview(field)
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Avvia")
        alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let parts = field.stringValue.split(separator: ":")
        if type.indexOfSelectedItem == 2 {
            guard let port = Int(field.stringValue), (1...65_535).contains(port) else { return showErrorMessage("Porta SOCKS non valida.") }
            openSession(host: host, mode: .dynamicForward(localPort: port))
        } else {
            guard parts.count == 3, let firstPort = Int(parts[0]), let secondPort = Int(parts[2]) else { return showErrorMessage("Usa il formato porta:host:porta.") }
            let mode: SSHLaunchMode = type.indexOfSelectedItem == 0
                ? .localForward(localPort: firstPort, remoteHost: String(parts[1]), remotePort: secondPort)
                : .remoteForward(remotePort: firstPort, localHost: String(parts[1]), localPort: secondPort)
            openSession(host: host, mode: mode)
        }
    }

    private func showError(_ error: Error) { showErrorMessage(error.localizedDescription) }
    private func showErrorMessage(_ message: String) {
        let alert = NSAlert(); alert.messageText = "MySSH"; alert.informativeText = message; alert.runModal()
    }
}

@MainActor
extension MainViewController: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        guard let index = sessions.firstIndex(where: { $0.terminal === source }) else { return }
        sessions[index].isRunning = false
        if selectedSessionIndex == index { statusLabel.stringValue = exitCode == 0 ? "Disconnesso" : "Terminato (codice \(exitCode.map(String.init) ?? "-") )" }
    }
}

private struct TerminalSession {
    let id: UUID
    var title: String
    let host: MySSHCore.Host
    let terminal: LocalProcessTerminalView
    var isRunning = true
}

@MainActor
final class HostCollectionItem: NSCollectionViewItem {
    private let iconTile = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var accentColor = NSColor.systemBlue

    override var isSelected: Bool {
        didSet { updateSelectionStyle() }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.borderWidth = 1

        iconTile.wantsLayer = true
        iconTile.layer?.cornerRadius = 10
        iconTile.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = MDTheme.text
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = MDTheme.mutedText
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(iconTile)
        iconTile.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            iconTile.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 48),
            iconTile.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: view.centerYAnchor, constant: -2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 3)
        ])
        updateSelectionStyle()
    }

    func configure(with host: MySSHCore.Host) {
        accentColor = Self.color(for: host)
        iconTile.layer?.backgroundColor = accentColor.cgColor
        iconView.image = NSImage(
            systemSymbolName: host.symbolName ?? (host.isFavorite ? "star.fill" : "server.rack"),
            accessibilityDescription: host.name
        )
        titleLabel.stringValue = host.name
        subtitleLabel.stringValue = "\(host.hostname)  •  \(host.group ?? "Senza gruppo")"
        updateSelectionStyle()
    }

    private func updateSelectionStyle() {
        view.layer?.backgroundColor = isSelected
            ? MDTheme.surfaceRaised.cgColor
            : MDTheme.surface.cgColor
        view.layer?.borderColor = isSelected
            ? accentColor.cgColor
            : MDTheme.border.withAlphaComponent(0.55).cgColor
    }

    private static func color(for host: MySSHCore.Host) -> NSColor {
        let palette: [NSColor] = [MDTheme.cyan, MDTheme.pink, MDTheme.orange, MDTheme.green]
        let source = host.group ?? host.name
        let index = source.utf8.reduce(0) { ($0 + Int($1)) % palette.count }
        return palette[index]
    }
}

@MainActor
final class HostEditorController: NSViewController {
    var onSave: ((MySSHCore.Host, String?, String?) -> Void)?
    var onCancel: (() -> Void)?
    private var host: MySSHCore.Host
    private let groups: [String]
    private let tagSuggestions: [String]
    private let credential: String?
    private let nameField = NSTextField()
    private let hostnameField = NSTextField()
    private let portField = NSTextField()
    private let usernameField = NSTextField()
    private let authPopup = NSPopUpButton()
    private let identityField = NSTextField()
    private let secretField = NSSecureTextField()
    private let visibleSecretField = NSTextField()
    private let secretToggleButton = NSButton()
    private var isSecretVisible = false
    private let groupField = NSComboBox()
    private let tagsField = NSTextField()
    private let tagPopup = NSPopUpButton()
    private let notesField = NSTextField()
    private let favoriteCheck = NSButton(checkboxWithTitle: "Preferito", target: nil, action: nil)

    init(host: MySSHCore.Host, groups: [String], tagSuggestions: [String], credential: String?) {
        self.host = host
        self.groups = groups
        self.tagSuggestions = tagSuggestions
        self.credential = credential
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 700))
        authPopup.addItems(withTitles: ["Password", "Chiave SSH"])
        nameField.stringValue = host.name
        hostnameField.stringValue = host.hostname
        portField.stringValue = String(host.port)
        usernameField.stringValue = host.username
        authPopup.selectItem(at: host.authentication == .password ? 0 : 1)
        identityField.stringValue = host.identityFile ?? ""
        groupField.addItems(withObjectValues: groups)
        groupField.completes = true
        groupField.placeholderString = groups.isEmpty ? "Nuovo gruppo" : "Scegli o scrivi un gruppo"
        groupField.stringValue = host.group ?? ""
        tagsField.stringValue = host.tags.joined(separator: ", ")
        tagsField.placeholderString = "Tag separati da virgola"
        notesField.stringValue = host.notes
        favoriteCheck.state = host.isFavorite ? .on : .off
        secretField.stringValue = credential ?? ""
        visibleSecretField.stringValue = credential ?? ""
        secretField.placeholderString = "Password non salvata"
        visibleSecretField.placeholderString = "Password non salvata"
        let secretControl = makeSecretControl()
        let tagsControl = makeTagsControl()

        let heading = NSTextField(labelWithString: host.name.isEmpty ? "Nuovo host" : "Modifica host")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false
        let grid = NSGridView(views: [
            row("Nome", nameField), row("Hostname / IP", hostnameField), row("Porta", portField), row("Username", usernameField),
            row("Autenticazione", authPopup), row("File chiave", identityField), row("Password / passphrase", secretControl),
            row("Gruppo", groupField), row("Tag", tagsControl), row("Note", notesField), row("", favoriteCheck)
        ])
        grid.rowSpacing = 10; grid.columnSpacing = 12; grid.translatesAutoresizingMaskIntoConstraints = false
        let cancel = NSButton(title: "Annulla", target: self, action: #selector(cancelAction))
        let save = NSButton(title: "Salva", target: self, action: #selector(saveAction)); save.keyEquivalent = "\r"; save.bezelStyle = .rounded
        let buttons = NSStackView(views: [cancel, save]); buttons.orientation = .horizontal; buttons.spacing = 8; buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heading); view.addSubview(grid); view.addSubview(buttons)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), grid.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 24),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    private func row(_ title: String, _ control: NSView) -> [NSView] {
        let label = NSTextField(labelWithString: title); label.alignment = .right
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 290).isActive = true
        return [label, control]
    }

    private func makeSecretControl() -> NSView {
        let container = NSView()
        [secretField, visibleSecretField, secretToggleButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        visibleSecretField.isHidden = true
        secretToggleButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Mostra password")
        secretToggleButton.bezelStyle = .inline
        secretToggleButton.isBordered = false
        secretToggleButton.toolTip = "Mostra password"
        secretToggleButton.target = self
        secretToggleButton.action = #selector(toggleSecretVisibility)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 26),
            secretField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            secretField.trailingAnchor.constraint(equalTo: secretToggleButton.leadingAnchor, constant: -6),
            secretField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            visibleSecretField.leadingAnchor.constraint(equalTo: secretField.leadingAnchor),
            visibleSecretField.trailingAnchor.constraint(equalTo: secretField.trailingAnchor),
            visibleSecretField.centerYAnchor.constraint(equalTo: secretField.centerYAnchor),
            secretToggleButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            secretToggleButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            secretToggleButton.widthAnchor.constraint(equalToConstant: 24)
        ])
        return container
    }

    private func makeTagsControl() -> NSView {
        let container = NSView()
        tagsField.translatesAutoresizingMaskIntoConstraints = false
        tagPopup.translatesAutoresizingMaskIntoConstraints = false
        tagPopup.addItems(withTitles: ["Aggiungi tag…"] + tagSuggestions)
        tagPopup.target = self
        tagPopup.action = #selector(appendSuggestedTag)
        container.addSubview(tagsField)
        container.addSubview(tagPopup)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 26),
            tagsField.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tagsField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            tagsField.trailingAnchor.constraint(equalTo: tagPopup.leadingAnchor, constant: -6),
            tagPopup.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tagPopup.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            tagPopup.widthAnchor.constraint(equalToConstant: 125)
        ])
        return container
    }

    @objc private func appendSuggestedTag() {
        guard tagPopup.indexOfSelectedItem > 0, let selected = tagPopup.titleOfSelectedItem else { return }
        var current = tagsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !current.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            current.append(selected)
            tagsField.stringValue = current.joined(separator: ", ")
        }
        tagPopup.selectItem(at: 0)
    }

    @objc private func toggleSecretVisibility() {
        isSecretVisible.toggle()
        if isSecretVisible {
            visibleSecretField.stringValue = secretField.stringValue
        } else {
            secretField.stringValue = visibleSecretField.stringValue
        }
        secretField.isHidden = isSecretVisible
        visibleSecretField.isHidden = !isSecretVisible
        let symbol = isSecretVisible ? "eye.slash" : "eye"
        let description = isSecretVisible ? "Nascondi password" : "Mostra password"
        secretToggleButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        secretToggleButton.toolTip = description
        view.window?.makeFirstResponder(isSecretVisible ? visibleSecretField : secretField)
    }

    @objc private func cancelAction() { onCancel?() }
    @objc private func saveAction() {
        host.name = nameField.stringValue
        host.hostname = hostnameField.stringValue
        host.port = Int(portField.stringValue) ?? 0
        host.username = usernameField.stringValue
        host.authentication = authPopup.indexOfSelectedItem == 0 ? .password : .privateKey
        host.identityFile = identityField.stringValue.isEmpty ? nil : identityField.stringValue
        host.group = groupField.stringValue.isEmpty ? nil : groupField.stringValue
        host.tags = tagsField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        host.notes = notesField.stringValue
        host.isFavorite = favoriteCheck.state == .on
        let currentSecret = isSecretVisible ? visibleSecretField.stringValue : secretField.stringValue
        let secret = currentSecret.isEmpty ? nil : currentSecret
        onSave?(host, host.authentication == .password ? secret : nil, host.authentication == .privateKey ? secret : nil)
    }
}

private extension NSToolbarItem.Identifier {
    static let add = Self("addHost"), importConfig = Self("importConfig"), portableImport = Self("portableImport"), portableExport = Self("portableExport"), edit = Self("editHost"), delete = Self("deleteHost")
    static let connect = Self("connect"), disconnect = Self("disconnect"), newTab = Self("newTab")
    static let sftp = Self("sftp"), snippets = Self("snippets"), forward = Self("forward")
}

private extension NSUserInterfaceItemIdentifier {
    static let hostCard = Self("HostCollectionItem")
}
