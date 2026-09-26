import Foundation
import Combine
import MySSHCore

typealias ServerHost = MySSHCore.Host

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var hosts: [ServerHost] = []
    @Published var selectedHostID: UUID?
    @Published var editorHost: ServerHost?
    @Published var searchText = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var unavailableFeature: String?
    @Published var isTransferPresented = false

    private let service: HostService

    init(service: HostService? = nil) {
        self.service = service ?? HostService(persistence: AppDataStore(), secrets: KeychainStore())
    }

    var selectedHost: ServerHost? { hosts.first { $0.id == selectedHostID } }

    var filteredHosts: [ServerHost] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return hosts }
        return hosts.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.hostname.localizedCaseInsensitiveContains(query)
                || $0.username.localizedCaseInsensitiveContains(query)
                || ($0.group?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            hosts = try await service.loadHosts()
            if selectedHostID == nil { selectedHostID = hosts.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createHost() { editorHost = .empty }
    func editSelectedHost() { editorHost = selectedHost }

    func save(_ host: ServerHost, password: String?, passphrase: String?) async -> Bool {
        do {
            hosts = try await service.save(host: host, password: password, passphrase: passphrase)
            selectedHostID = host.id
            editorHost = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ host: ServerHost) async {
        do {
            hosts = try await service.delete(id: host.id)
            if selectedHostID == host.id { selectedHostID = hosts.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ host: ServerHost) async {
        do { hosts = try await service.duplicate(host) }
        catch { errorMessage = error.localizedDescription }
    }

    func toggleFavorite(_ host: ServerHost) async {
        var updated = host
        updated.isFavorite.toggle()
        _ = await save(updated, password: nil, passphrase: nil)
    }

    func showUnavailable(_ feature: String) { unavailableFeature = feature }

    func sshPassword(for host: ServerHost) async -> String? {
        do { return try await service.credential(for: host) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func exportPortableArchive(passphrase: String) async -> Data? {
        do { return try await service.exportPortableArchive(passphrase: passphrase) }
        catch { errorMessage = error.localizedDescription; return nil }
    }

    func importPortableArchive(_ data: Data, passphrase: String) async -> Bool {
        do {
            hosts = try await service.importPortableArchive(data, passphrase: passphrase)
            selectedHostID = hosts.first?.id
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
