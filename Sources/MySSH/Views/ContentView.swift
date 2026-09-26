import SwiftUI
import MySSHCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sessions: [IPadTerminalSession] = []

    var body: some View {
        NavigationSplitView {
            HostSidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 360)
        } detail: {
            if !sessions.isEmpty {
                SessionWorkspace(hosts: $sessions, availableHosts: model.hosts)
            } else if let host = model.selectedHost {
                HostDetailView(host: host, onOpenSession: openSession)
            } else {
                ContentUnavailableView(
                    "Nessun host selezionato",
                    systemImage: "terminal",
                    description: Text("Crea un host per iniziare.")
                )
            }
        }
        .toolbar { AppToolbar() }
        .sheet(item: $model.editorHost) { host in HostEditorView(host: host) }
        .sheet(isPresented: $model.isTransferPresented) { PortableTransferView() }
        .alert("MySSH", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Non ancora disponibile", isPresented: unavailableBinding) {
            Button("OK", role: .cancel) { model.unavailableFeature = nil }
        } message: {
            Text("\(model.unavailableFeature ?? "Questa funzione") sarà implementata in una milestone successiva.")
        }
    }

    private func openSession(_ host: ServerHost) {
        if !sessions.contains(where: { $0.id == host.id }) {
            sessions.append(IPadTerminalSession(host: host))
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var unavailableBinding: Binding<Bool> {
        Binding(get: { model.unavailableFeature != nil }, set: { if !$0 { model.unavailableFeature = nil } })
    }
}

private struct SessionWorkspace: View {
    @Binding var sessions: [IPadTerminalSession]
    let availableHosts: [ServerHost]
    @State private var selectedID: UUID?

    init(hosts: Binding<[IPadTerminalSession]>, availableHosts: [ServerHost]) {
        _sessions = hosts
        self.availableHosts = availableHosts
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Menu { ForEach(availableHosts) { host in Button(host.name) { if !sessions.contains(where: { $0.id == host.id }) { sessions.append(IPadTerminalSession(host: host)); selectedID = host.id } } } } label: { Label("Nuova sessione", systemImage: "plus") }
                Spacer()
            }.padding(.horizontal).padding(.top, 8)
            TabView(selection: $selectedID) {
                ForEach(sessions) { session in
                    RemoteTerminalView(session: session, onClose: { sessions.removeAll { $0.id == session.id }; selectedID = sessions.first?.id })
                        .tag(Optional(session.id)).tabItem { Text(session.host.name) }
                }
            }
        }.onAppear { if selectedID == nil { selectedID = sessions.first?.id } }
    }
}

private struct AppToolbar: ToolbarContent {
    @EnvironmentObject private var model: AppModel

    var body: some ToolbarContent {
#if os(macOS)
        ToolbarItemGroup {
            Button { model.showUnavailable("La connessione SSH") } label: { Label("Connetti", systemImage: "bolt.fill") }
                .disabled(model.selectedHost == nil)
            Button { model.showUnavailable("Le sessioni multiple") } label: { Label("Nuovo tab", systemImage: "plus.square.on.square") }
            Button { model.showUnavailable("SFTP") } label: { Label("SFTP", systemImage: "folder") }
            Button { model.showUnavailable("Gli snippet") } label: { Label("Snippet", systemImage: "chevron.left.forwardslash.chevron.right") }
            Button { model.showUnavailable("Il port forwarding") } label: { Label("Forwarding", systemImage: "arrow.triangle.branch") }
            Button { model.isTransferPresented = true } label: { Label("Trasferisci", systemImage: "arrow.up.arrow.down.circle") }
            SettingsLink { Label("Impostazioni", systemImage: "gear") }
        }
#else
        ToolbarItem(placement: .primaryAction) {
            Button { model.isTransferPresented = true } label: {
                Label("Importa o esporta", systemImage: "arrow.up.arrow.down.circle")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button { model.showUnavailable("La connessione SSH") } label: { Label("Connetti", systemImage: "bolt.fill") }
                Button { model.showUnavailable("Le sessioni multiple") } label: { Label("Nuovo tab", systemImage: "plus.square.on.square") }
                Button { model.showUnavailable("SFTP") } label: { Label("SFTP", systemImage: "folder") }
                Button { model.showUnavailable("Gli snippet") } label: { Label("Snippet", systemImage: "chevron.left.forwardslash.chevron.right") }
                Button { model.showUnavailable("Il port forwarding") } label: { Label("Forwarding", systemImage: "arrow.triangle.branch") }
            } label: {
                Label("Azioni", systemImage: "ellipsis.circle")
            }
        }
#endif
    }
}
