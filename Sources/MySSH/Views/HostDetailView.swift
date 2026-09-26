import SwiftUI
import MySSHCore
#if os(iOS)
import UIKit
import SwiftTerm
#endif

struct HostDetailView: View {
    @EnvironmentObject private var model: AppModel
    let host: ServerHost
    @State private var standaloneSession: IPadTerminalSession?
    var onOpenSession: ((ServerHost) -> Void)?

    var body: some View {
        Group {
            if let standaloneSession {
                RemoteTerminalView(session: standaloneSession, onClose: { self.standaloneSession = nil })
            } else {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: host.symbolName ?? "server.rack")
                .font(.system(size: 52)).foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text(host.name).font(.largeTitle.bold())
                Text(host.endpoint).font(.title3.monospaced()).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Connetti") { if let onOpenSession { onOpenSession(host) } else { standaloneSession = IPadTerminalSession(host: host) } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Modifica") { model.editorHost = host }.controlSize(.large)
            }
            if !host.tags.isEmpty {
                Text(host.tags.map { "#\($0)" }.joined(separator: "  ")).foregroundStyle(.secondary)
            }
            if !host.notes.isEmpty {
                Text(host.notes).frame(maxWidth: 520).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(host.name)
            }
        }
    }
}

@MainActor
final class IPadTerminalSession: ObservableObject, Identifiable {
    let id: UUID
    let host: ServerHost
    @Published var output = ""
    @Published var status = "Connessione…"

    private var client: IOSSSHClient?
    private var isConnecting = false

    init(host: ServerHost) {
        id = host.id
        self.host = host
    }

    func connect(using model: AppModel) async {
        guard client == nil, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        guard host.authentication == .password,
              let password = await model.sshPassword(for: host),
              !password.isEmpty else {
            status = "Password SSH mancante"
            return
        }
        let terminal = IOSSSHClient()
        client = terminal
        do {
            try await terminal.connect(host: host.hostname, port: host.port, username: host.username, password: password) { [weak self] text in
                Task { @MainActor in self?.output += text }
            }
            status = "Connesso"
        } catch {
            client = nil
            status = "Errore: \(error.localizedDescription)"
        }
    }

    func send(_ text: String) {
        Task { try? await client?.send(text) }
    }

    func disconnect() async {
        await client?.disconnect()
        client = nil
        status = "Disconnesso"
    }
}

struct RemoteTerminalView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: IPadTerminalSession
    let onClose: () -> Void
    @State private var snippets = TerminalSnippet.load()
    @State private var isSnippetPanelPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.host.name).font(.headline)
                Spacer(); Text(session.status).foregroundStyle(.secondary)
                Button("Chiudi") { Task { await session.disconnect(); onClose() } }
            }.padding()
            InteractiveTerminal(output: $session.output, onInput: { session.send($0) })
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(IPadTerminalTheme.swiftUIBackground)
            HStack {
                Menu {
                    ForEach(snippets) { snippet in
                        Button { runSnippet(id: snippet.id) } label: {
                            Label(snippet.name, systemImage: "terminal")
                        }
                    }
                } label: {
                    Label("Snippet", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button { isSnippetPanelPresented = true } label: { Image(systemName: "slider.horizontal.3") }
                Text("Scrivi direttamente nel terminale").foregroundStyle(.secondary)
                Spacer()
            }.padding()
        }
        .task { await session.connect(using: model) }
        .sheet(isPresented: $isSnippetPanelPresented) { SnippetPanel(snippets: $snippets) }
        .onChange(of: snippets) { _, value in TerminalSnippet.save(value) }
    }

    private func runSnippet(id: UUID) {
        guard let command = snippets.first(where: { $0.id == id })?.command else { return }
        send(command)
    }

    private func send(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.send(command.hasSuffix("\n") ? command : command + "\n")
    }
}

private enum TerminalDisplay {
    static func apply(_ incoming: String, to current: String) -> String {
        var text = incoming
        text = text.replacingOccurrences(of: "\u{1B}[?2004h", with: "")
        text = text.replacingOccurrences(of: "\u{1B}[?2004l", with: "")
        var result = current
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 8, 127:
                if !result.isEmpty { result.removeLast() }
            case 13:
                break
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

#if os(iOS)
@MainActor
private enum IPadTerminalTheme {
    static let background = UIColor(red: 0.055, green: 0.071, blue: 0.125, alpha: 1)
    static let foreground = UIColor(red: 0.050, green: 0.900, blue: 0.490, alpha: 1)
    static let muted = UIColor(red: 0.570, green: 0.610, blue: 0.710, alpha: 1)
    static let cyan = UIColor(red: 0.055, green: 0.790, blue: 0.870, alpha: 1)
    static let pink = UIColor(red: 0.965, green: 0.160, blue: 0.365, alpha: 1)
    static let green = UIColor(red: 0.190, green: 0.820, blue: 0.410, alpha: 1)
    static let orange = UIColor(red: 0.965, green: 0.620, blue: 0.145, alpha: 1)
    static let swiftUIBackground = SwiftUI.Color(uiColor: background)

    static let palette: [SwiftTerm.Color] = [
        background, pink, green, orange,
        UIColor(red: 0.300, green: 0.520, blue: 0.980, alpha: 1),
        UIColor(red: 0.720, green: 0.350, blue: 0.950, alpha: 1),
        cyan, foreground,
        muted, UIColor(red: 1.000, green: 0.320, blue: 0.470, alpha: 1),
        UIColor(red: 0.330, green: 0.900, blue: 0.530, alpha: 1),
        UIColor(red: 1.000, green: 0.760, blue: 0.300, alpha: 1),
        UIColor(red: 0.430, green: 0.650, blue: 1.000, alpha: 1),
        UIColor(red: 0.850, green: 0.500, blue: 1.000, alpha: 1),
        UIColor(red: 0.250, green: 0.900, blue: 0.940, alpha: 1),
        .white
    ].map { SwiftTerm.Color(uiColor: $0) }
}

private struct InteractiveTerminal: UIViewRepresentable {
    @Binding var output: String
    let onInput: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.backspaceSendsControlH = false // SSH/Linux standard: DEL (0x7F)
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = IPadTerminalTheme.background
        view.nativeForegroundColor = IPadTerminalTheme.foreground
        view.caretColor = IPadTerminalTheme.cyan
        view.caretTextColor = IPadTerminalTheme.background
        view.selectedTextBackgroundColor = IPadTerminalTheme.cyan.withAlphaComponent(0.28)
        view.selectedTextForegroundColor = IPadTerminalTheme.foreground
        view.installColors(IPadTerminalTheme.palette)
        return view
    }
    func updateUIView(_ view: TerminalView, context: Context) { if output.utf8.count > context.coordinator.fedBytes { let bytes = Array(output.utf8.dropFirst(context.coordinator.fedBytes)); context.coordinator.fedBytes += bytes.count; view.feed(byteArray: bytes[...]) } }
    final class Coordinator: NSObject, TerminalViewDelegate {
        var parent: InteractiveTerminal; var fedBytes = 0
        init(_ parent: InteractiveTerminal) { self.parent = parent }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { parent.onInput(String(decoding: data, as: UTF8.self)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) { UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text") }
        func clipboardRead(source: TerminalView) -> Data? { UIPasteboard.general.data(forPasteboardType: "public.utf8-plain-text") }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
#else
private struct InteractiveTerminal: View { @Binding var output: String; let onInput: (String) -> Void; var body: some View { Text(output).textSelection(.enabled) } }
#endif

private struct TerminalSnippet: Identifiable, Codable, Hashable {
    var id = UUID(); var name: String; var command: String
    static let key = "ipadTerminalSnippets"
    static func load() -> [Self] { guard let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode([Self].self, from: data) else { return [] }; return value }
    static func save(_ value: [Self]) { UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key) }
}

private struct SnippetPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var snippets: [TerminalSnippet]
    @State private var selectedID: UUID?
    var body: some View {
        NavigationStack {
            List(selection: $selectedID) { ForEach(snippets) { snippet in VStack(alignment: .leading) { Text(snippet.name); Text(snippet.command).font(.caption.monospaced()).lineLimit(1).foregroundStyle(.secondary) } }.onDelete { snippets.remove(atOffsets: $0) } }
                .navigationTitle("Snippet")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button { let snippet = TerminalSnippet(name: "Nuovo snippet", command: ""); snippets.append(snippet); selectedID = snippet.id } label: { Image(systemName: "plus") } }
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                }
            if let index = snippets.firstIndex(where: { $0.id == selectedID }) {
                Form { TextField("Nome", text: $snippets[index].name); TextField("Comando", text: $snippets[index].command, axis: .vertical).lineLimit(4...10) }.padding()
            } else { ContentUnavailableView("Seleziona uno snippet", systemImage: "chevron.left.forwardslash.chevron.right") }
        }
    }
}
