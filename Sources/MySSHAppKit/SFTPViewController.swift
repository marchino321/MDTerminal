import AppKit
import MySSHCore

private struct RemoteEntry: Sendable {
    let name: String
    let isDirectory: Bool
    let size: Int64
}

private struct RemoteDragItem: Codable, Sendable {
    let path: String
    let isDirectory: Bool
}

private extension NSPasteboard.PasteboardType {
    static let mdTerminalRemoteEntry = Self("com.mdterminal.sftp.remote-entry")
}

private enum SFTPError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): message.isEmpty ? "Operazione SFTP fallita." : message
        }
    }
}

@MainActor
final class SFTPViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSSplitViewDelegate {
    private let host: MySSHCore.Host
    private let askPassPath: String?
    private var localDirectory = FileManager.default.homeDirectoryForCurrentUser
    private var remoteDirectory = "/"
    private var allLocalFiles: [URL] = []
    private var allRemoteEntries: [RemoteEntry] = []
    private var localFiles: [URL] = []
    private var remoteEntries: [RemoteEntry] = []
    private var localBackHistory: [URL] = []
    private var localForwardHistory: [URL] = []
    private var remoteBackHistory: [String] = []
    private var remoteForwardHistory: [String] = []

    private let localPath = NSTextField()
    private let remotePath = NSTextField()
    private let localSearch = NSSearchField()
    private let remoteSearch = NSSearchField()
    private let localTable = NSTableView()
    private let remoteTable = NSTableView()
    private let splitView = NSSplitView()
    private let progress = NSProgressIndicator()
    private let status = NSTextField(labelWithString: "Pronto")
    private let uploadButton = NSButton(title: "Upload", target: nil, action: nil)
    private let downloadButton = NSButton(title: "Download", target: nil, action: nil)

    init(host: MySSHCore.Host, askPassPath: String?) {
        self.host = host
        self.askPassPath = askPassPath
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        configureInterface()
        refreshLocal()
        Task { await refreshRemote() }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard splitView.arrangedSubviews.count == 2 else { return }
        let midpoint = (splitView.bounds.width - splitView.dividerThickness) / 2
        if abs(splitView.arrangedSubviews[0].frame.width - midpoint) > 0.5 {
            splitView.setPosition(midpoint, ofDividerAt: 0)
        }
    }

    private func configureInterface() {
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Aggiorna")!, target: self, action: #selector(refreshAction))
        let newFolder = NSButton(title: "Nuova cartella", target: self, action: #selector(createFolder))
        let rename = NSButton(title: "Rinomina", target: self, action: #selector(renameRemote))
        let delete = NSButton(title: "Elimina", target: self, action: #selector(deleteRemote))
        uploadButton.target = self; uploadButton.action = #selector(chooseUpload)
        downloadButton.target = self; downloadButton.action = #selector(downloadSelected)
        header.addArrangedSubview(uploadButton); header.addArrangedSubview(downloadButton)
        header.addArrangedSubview(newFolder); header.addArrangedSubview(rename); header.addArrangedSubview(delete)
        header.addArrangedSubview(NSView()); header.addArrangedSubview(refresh)

        localPath.stringValue = localDirectory.path
        localPath.target = self; localPath.action = #selector(localPathChanged)
        remotePath.stringValue = remoteDirectory
        remotePath.target = self; remotePath.action = #selector(remotePathChanged)
        localSearch.placeholderString = "Cerca nella cartella locale"
        remoteSearch.placeholderString = "Cerca nella cartella remota"
        localSearch.delegate = self; remoteSearch.delegate = self

        configureTable(localTable, identifier: "local", title: "LOCALE")
        configureTable(remoteTable, identifier: "remote", title: "REMOTO")
        localTable.allowsMultipleSelection = true
        remoteTable.allowsMultipleSelection = true
        localTable.setDraggingSourceOperationMask(.copy, forLocal: true)
        localTable.setDraggingSourceOperationMask(.copy, forLocal: false)
        localTable.registerForDraggedTypes([.mdTerminalRemoteEntry])
        remoteTable.setDraggingSourceOperationMask(.copy, forLocal: true)
        remoteTable.setDraggingSourceOperationMask(.copy, forLocal: false)
        remoteTable.registerForDraggedTypes([.fileURL])

        let localPanel = makePanel(title: "LOCALE", pathField: localPath, searchField: localSearch, table: localTable, isRemote: false)
        let remotePanel = makePanel(title: "REMOTO — trascina qui i file", pathField: remotePath, searchField: remoteSearch, table: remoteTable, isRemote: true)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(localPanel)
        splitView.addArrangedSubview(remotePanel)

        progress.style = .bar; progress.isIndeterminate = true; progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        status.textColor = .secondaryLabelColor; status.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header); view.addSubview(splitView); view.addSubview(progress); view.addSubview(status)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), header.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor), splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor), splitView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10), splitView.bottomAnchor.constraint(equalTo: progress.topAnchor, constant: -10),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), progress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), progress.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -5),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        (splitView.bounds.width - splitView.dividerThickness) / 2
    }

    private func configureTable(_ table: NSTableView, identifier: String, title: String) {
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(identifier).name")); name.title = title; name.width = 340
        let size = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(identifier).size")); size.title = "Dimensione"; size.width = 100
        table.addTableColumn(name); table.addTableColumn(size)
        table.delegate = self; table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        table.doubleAction = identifier == "local" ? #selector(openLocalSelection) : #selector(openRemoteSelection)
        table.target = self
    }

    private func makePanel(title: String, pathField: NSTextField, searchField: NSSearchField, table: NSTableView, isRemote: Bool) -> NSView {
        let panel = NSView()
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 12, weight: .semibold)
        let back = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Indietro")!, target: self, action: isRemote ? #selector(remoteBack) : #selector(localBack))
        let forward = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Avanti")!, target: self, action: isRemote ? #selector(remoteForward) : #selector(localForward))
        let up = NSButton(image: NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Cartella superiore")!, target: self, action: isRemote ? #selector(remoteUp) : #selector(localUp))
        [back, forward, up].forEach { $0.bezelStyle = .texturedRounded }
        let navigation = NSStackView(views: [back, forward, up, pathField]); navigation.orientation = .horizontal; navigation.spacing = 5
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        [label, navigation, searchField, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview($0) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12), label.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            navigation.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10), navigation.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10), navigation.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10), searchField.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10), searchField.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor), scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
        return panel
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === localTable ? localFiles.count : remoteEntries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isName = tableColumn?.identifier.rawValue.hasSuffix(".name") == true
        let text: String
        let icon: NSImage?
        if tableView === localTable {
            let url = localFiles[row]
            text = isName ? url.lastPathComponent : formattedSize(localSize(url))
            icon = isName ? NSWorkspace.shared.icon(forFile: url.path) : nil
        } else {
            let entry = remoteEntries[row]
            text = isName ? entry.name : (entry.isDirectory ? "—" : formattedSize(entry.size))
            icon = isName ? NSImage(systemSymbolName: entry.isDirectory ? "folder.fill" : "doc", accessibilityDescription: nil) : nil
        }
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text); field.lineBreakMode = .byTruncatingMiddle; field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        if let icon {
            let image = NSImageView(image: icon); image.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(image)
            NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18), field.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6)])
        } else { field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6).isActive = true }
        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
        field.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        if tableView === localTable {
            return localFiles[row] as NSURL
        }
        guard tableView === remoteTable, remoteEntries.indices.contains(row) else { return nil }
        let entry = remoteEntries[row]
        let item = NSPasteboardItem()
        let payload = RemoteDragItem(path: appendRemote(entry.name), isDirectory: entry.isDirectory)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        item.setData(data, forType: .mdTerminalRemoteEntry)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        if tableView === remoteTable, fileURLs(from: info.draggingPasteboard).isEmpty == false {
            let canDropOnFolder = remoteEntries.indices.contains(row) && remoteEntries[row].isDirectory
            tableView.setDropRow(canDropOnFolder ? row : -1, dropOperation: canDropOnFolder ? .on : .above)
            return .copy
        }
        if tableView === localTable, remoteDragItems(from: info.draggingPasteboard).isEmpty == false {
            let canDropOnFolder = localFiles.indices.contains(row) && isDirectory(localFiles[row])
            tableView.setDropRow(canDropOnFolder ? row : -1, dropOperation: canDropOnFolder ? .on : .above)
            return .copy
        }
        return []
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        if tableView === remoteTable {
            let urls = fileURLs(from: info.draggingPasteboard)
            guard !urls.isEmpty else { return false }
            let destination = remoteEntries.indices.contains(row) && remoteEntries[row].isDirectory
                ? appendRemote(remoteEntries[row].name)
                : remoteDirectory
            upload(urls, destination: destination)
            return true
        }
        if tableView === localTable {
            let items = remoteDragItems(from: info.draggingPasteboard)
            guard !items.isEmpty else { return false }
            let destination = localFiles.indices.contains(row) && isDirectory(localFiles[row])
                ? localFiles[row]
                : localDirectory
            download(items, destination: destination)
            return true
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        if field === localSearch { applyLocalFilter() }
        if field === remoteSearch { applyRemoteFilter() }
    }

    private func refreshLocal() {
        do {
            allLocalFiles = try FileManager.default.contentsOfDirectory(at: localDirectory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles])
                .sorted { left, right in
                    let leftDirectory = self.isDirectory(left), rightDirectory = self.isDirectory(right)
                    return leftDirectory == rightDirectory
                        ? left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
                        : leftDirectory
                }
            localPath.stringValue = localDirectory.path
            applyLocalFilter()
        } catch { showError(error.localizedDescription) }
    }

    private func applyLocalFilter() {
        let query = localSearch.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        localFiles = query.isEmpty ? allLocalFiles : allLocalFiles.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
        localTable.reloadData()
    }

    private func applyRemoteFilter() {
        let query = remoteSearch.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteEntries = query.isEmpty ? allRemoteEntries : allRemoteEntries.filter { $0.name.localizedCaseInsensitiveContains(query) }
        remoteTable.reloadData()
        if !query.isEmpty { status.stringValue = "\(remoteEntries.count) risultati in \(remoteDirectory)" }
    }

    private func refreshRemote() async {
        setBusy(true, "Lettura di \(remoteDirectory)…")
        do {
            let quoted = shellQuote(remoteDirectory)
            let command = "LC_ALL=C find \(quoted) -mindepth 1 -maxdepth 1 -printf '%f\\t%y\\t%s\\n'"
            let result = try await run(executable: "/usr/bin/ssh", arguments: sshArguments() + [remoteTarget, command])
            allRemoteEntries = result.split(separator: "\n").compactMap { line in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard fields.count >= 3 else { return nil }
                return RemoteEntry(name: String(fields[0]), isDirectory: fields[1] == "d", size: Int64(fields[2]) ?? 0)
            }.sorted { $0.isDirectory == $1.isDirectory ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.isDirectory }
            remotePath.stringValue = remoteDirectory
            applyRemoteFilter()
            setBusy(false, "\(allRemoteEntries.count) elementi — drop attivo in \(remoteDirectory)")
        } catch { setBusy(false, "Errore"); showError(error.localizedDescription) }
    }

    @objc private func refreshAction() { refreshLocal(); Task { await refreshRemote() } }
    @objc private func localPathChanged() { navigateLocal(to: URL(fileURLWithPath: NSString(string: localPath.stringValue).expandingTildeInPath)) }
    @objc private func remotePathChanged() { navigateRemote(to: normalizedRemote(remotePath.stringValue)) }
    @objc private func openLocalSelection() {
        guard localFiles.indices.contains(localTable.clickedRow), (try? localFiles[localTable.clickedRow].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
        navigateLocal(to: localFiles[localTable.clickedRow])
    }
    @objc private func openRemoteSelection() {
        guard remoteEntries.indices.contains(remoteTable.clickedRow), remoteEntries[remoteTable.clickedRow].isDirectory else { return }
        navigateRemote(to: appendRemote(remoteEntries[remoteTable.clickedRow].name))
    }

    private func navigateLocal(to directory: URL, recordHistory: Bool = true) {
        guard directory != localDirectory else { return refreshLocal() }
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return showError("La cartella locale non esiste.") }
        if recordHistory { localBackHistory.append(localDirectory); localForwardHistory.removeAll() }
        localDirectory = directory.standardizedFileURL; localSearch.stringValue = ""; refreshLocal()
    }

    private func navigateRemote(to directory: String, recordHistory: Bool = true) {
        let normalized = normalizedRemote(directory)
        if normalized == remoteDirectory {
            Task { await refreshRemote() }
            return
        }
        if recordHistory { remoteBackHistory.append(remoteDirectory); remoteForwardHistory.removeAll() }
        remoteDirectory = normalized; remoteSearch.stringValue = ""; Task { await refreshRemote() }
    }

    @objc private func localBack() {
        guard let destination = localBackHistory.popLast() else { return }
        localForwardHistory.append(localDirectory); navigateLocal(to: destination, recordHistory: false)
    }
    @objc private func localForward() {
        guard let destination = localForwardHistory.popLast() else { return }
        localBackHistory.append(localDirectory); navigateLocal(to: destination, recordHistory: false)
    }
    @objc private func localUp() { navigateLocal(to: localDirectory.deletingLastPathComponent()) }
    @objc private func remoteBack() {
        guard let destination = remoteBackHistory.popLast() else { return }
        remoteForwardHistory.append(remoteDirectory); navigateRemote(to: destination, recordHistory: false)
    }
    @objc private func remoteForward() {
        guard let destination = remoteForwardHistory.popLast() else { return }
        remoteBackHistory.append(remoteDirectory); navigateRemote(to: destination, recordHistory: false)
    }
    @objc private func remoteUp() {
        guard remoteDirectory != "/" else { return }
        let parent = NSString(string: remoteDirectory).deletingLastPathComponent
        navigateRemote(to: parent.isEmpty ? "/" : parent)
    }

    @objc private func chooseUpload() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { upload(panel.urls, destination: remoteDirectory) }
    }

    private func upload(_ urls: [URL], destination: String) {
        guard !urls.isEmpty else { return }
        Task {
            setBusy(true, "Upload di \(urls.count) elementi in \(destination)…")
            do {
                for url in urls {
                    try await runTransfer(executable: "/usr/bin/scp", arguments: scpArguments(recursive: isDirectory(url)) + [url.path, "\(remoteTarget):\(escapeRemote(destination))"])
                }
                await refreshRemote(); setBusy(false, "Upload completato")
            } catch { setBusy(false, "Upload fallito"); showError(error.localizedDescription) }
        }
    }

    @objc private func downloadSelected() {
        let indexes = remoteTable.selectedRowIndexes
        let items = indexes.compactMap { index -> RemoteDragItem? in
            guard remoteEntries.indices.contains(index) else { return nil }
            let entry = remoteEntries[index]
            return RemoteDragItem(path: appendRemote(entry.name), isDirectory: entry.isDirectory)
        }
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        download(items, destination: destination)
    }

    private func download(_ items: [RemoteDragItem], destination: URL) {
        Task {
            setBusy(true, "Download di \(items.count) elementi in \(destination.lastPathComponent)…")
            do {
                for item in items {
                    let source = "\(remoteTarget):\(escapeRemote(item.path))"
                    try await runTransfer(executable: "/usr/bin/scp", arguments: scpArguments(recursive: item.isDirectory) + [source, destination.path])
                }
                localDirectory = destination; refreshLocal(); setBusy(false, "Download completato")
            } catch { setBusy(false, "Download fallito"); showError(error.localizedDescription) }
        }
    }

    @objc private func createFolder() {
        prompt(title: "Nuova cartella", initial: "nuova-cartella") { [weak self] name in
            guard let self else { return }
            Task { await self.mutateRemote("mkdir -p \(self.shellQuote(self.appendRemote(name)))") }
        }
    }

    @objc private func renameRemote() {
        guard remoteEntries.indices.contains(remoteTable.selectedRow) else { return }
        let old = remoteEntries[remoteTable.selectedRow]
        prompt(title: "Rinomina", initial: old.name) { [weak self] name in
            guard let self else { return }
            Task { await self.mutateRemote("mv -- \(self.shellQuote(self.appendRemote(old.name))) \(self.shellQuote(self.appendRemote(name)))") }
        }
    }

    @objc private func deleteRemote() {
        guard remoteEntries.indices.contains(remoteTable.selectedRow) else { return }
        let entry = remoteEntries[remoteTable.selectedRow]
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Eliminare \(entry.name)?"; alert.informativeText = "L'operazione sul server non può essere annullata."; alert.addButton(withTitle: "Elimina"); alert.addButton(withTitle: "Annulla")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await mutateRemote("rm -rf -- \(shellQuote(appendRemote(entry.name)))") }
    }

    private func mutateRemote(_ command: String) async {
        setBusy(true, "Operazione in corso…")
        do { _ = try await run(executable: "/usr/bin/ssh", arguments: sshArguments() + [remoteTarget, command]); await refreshRemote() }
        catch { setBusy(false, "Errore"); showError(error.localizedDescription) }
    }

    private func runTransfer(executable: String, arguments: [String]) async throws { _ = try await run(executable: executable, arguments: arguments) }

    private func run(executable: String, arguments: [String]) async throws -> String {
        let environment = sshEnvironment()
        return try await Task.detached {
            let process = Process(); let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            process.environment = environment; process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else { throw SFTPError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return output
        }.value
    }

    private var remoteTarget: String { "\(host.username)@\(host.hostname)" }
    private func sshArguments() -> [String] { commonOptions() + ["-p", String(host.port)] + authenticationOptions() }
    private func scpArguments(recursive: Bool) -> [String] { (recursive ? ["-r"] : []) + commonOptions() + ["-P", String(host.port)] + authenticationOptions() }
    private func commonOptions() -> [String] { ["-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=30", "-o", "StrictHostKeyChecking=ask", "-o", "UpdateHostKeys=ask"] }
    private func authenticationOptions() -> [String] {
        if host.authentication == .password { return ["-o", "PreferredAuthentications=keyboard-interactive,password", "-o", "PubkeyAuthentication=no"] }
        return host.identityFile.map { ["-i", NSString(string: $0).expandingTildeInPath, "-o", "IdentitiesOnly=yes"] } ?? []
    }
    private func sshEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"; environment["SSH_ASKPASS_REQUIRE"] = "force"; environment["MYSSH_HOST_ID"] = host.id.uuidString
        if let askPassPath { environment["SSH_ASKPASS"] = askPassPath }
        return environment
    }

    private func appendRemote(_ name: String) -> String {
        let base = remoteDirectory == "/" ? "" : remoteDirectory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/" + [base, suffix].filter { !$0.isEmpty }.joined(separator: "/")
    }
    private func normalizedRemote(_ path: String) -> String { path.hasPrefix("/") ? path : "/" + path }
    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func escapeRemote(_ value: String) -> String { value.replacingOccurrences(of: " ", with: "\\ ") }
    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        return objects.compactMap { ($0 as? NSURL)?.filePathURL }
    }
    private func remoteDragItems(from pasteboard: NSPasteboard) -> [RemoteDragItem] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            guard let data = item.data(forType: .mdTerminalRemoteEntry) else { return nil }
            return try? JSONDecoder().decode(RemoteDragItem.self, from: data)
        }
    }
    private func isDirectory(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    private func localSize(_ url: URL) -> Int64 { Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    private func formattedSize(_ size: Int64) -> String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    private func setBusy(_ busy: Bool, _ message: String) {
        status.stringValue = message; progress.isHidden = !busy; busy ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        uploadButton.isEnabled = !busy; downloadButton.isEnabled = !busy
    }
    private func prompt(title: String, initial: String, completion: (String) -> Void) {
        let alert = NSAlert(); alert.messageText = title; let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24); alert.accessoryView = field; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Annulla")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty { completion(field.stringValue) }
    }
    private func showError(_ message: String) { let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "SFTP"; alert.informativeText = message; alert.runModal() }
}
