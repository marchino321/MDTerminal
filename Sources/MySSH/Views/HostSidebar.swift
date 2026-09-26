import SwiftUI
import MySSHCore

struct HostSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedHostID) {
            if !favorites.isEmpty { hostSection("Preferiti", icon: "star.fill", hosts: favorites) }
            if !recent.isEmpty { hostSection("Recenti", icon: "clock", hosts: recent) }
            hostSection("Tutti gli host", icon: "server.rack", hosts: ungrouped)
            ForEach(groups, id: \.self) { group in
                hostSection(group, icon: "folder", hosts: grouped[group] ?? [])
            }
        }
        .searchable(text: $model.searchText, prompt: "Cerca host")
        .navigationTitle("MD Terminal")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button { model.createHost() } label: {
                    Label("Nuovo", systemImage: "plus")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.055, green: 0.790, blue: 0.870))
                .controlSize(.large)
                    .help("Nuovo host")

                Button { model.isTransferPresented = true } label: {
                    Label("Importa", systemImage: "square.and.arrow.down")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.250, green: 0.310, blue: 0.460))
                .controlSize(.large)
                .help("Importa o esporta")

                if model.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var favorites: [ServerHost] { model.filteredHosts.filter(\.isFavorite) }
    private var recent: [ServerHost] {
        model.filteredHosts.filter { $0.lastConnectedAt != nil }
            .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
            .prefix(5).map { $0 }
    }
    private var grouped: [String: [ServerHost]] {
        Dictionary(grouping: model.filteredHosts.filter { normalizedGroup($0) != nil }) { normalizedGroup($0)! }
    }
    private var groups: [String] { grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    private var ungrouped: [ServerHost] { model.filteredHosts.filter { normalizedGroup($0) == nil } }

    @ViewBuilder
    private func hostSection(_ title: String, icon: String, hosts: [ServerHost]) -> some View {
        if !hosts.isEmpty {
            Section { ForEach(hosts) { HostRow(host: $0).tag($0.id) } } header: { Label(title, systemImage: icon) }
        }
    }

    private func normalizedGroup(_ host: ServerHost) -> String? {
        let value = host.group?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

private struct HostRow: View {
    @EnvironmentObject private var model: AppModel
    let host: ServerHost

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).lineLimit(1)
                Text(host.hostname).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        } icon: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: host.symbolName ?? "server.rack")
                    .frame(width: 24, height: 24)
                Circle().fill(.gray).frame(width: 7, height: 7)
            }
        }
        .contextMenu {
            Button(host.isFavorite ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti") { Task { await model.toggleFavorite(host) } }
            Button("Modifica…") { model.editorHost = host }
            Button("Duplica") { Task { await model.duplicate(host) } }
            Divider()
            Button("Elimina", role: .destructive) { Task { await model.delete(host) } }
        }
    }
}
