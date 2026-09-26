import Foundation

public actor HostService {
    private let persistence: any AppDataPersisting
    private let secrets: any SecretStoring

    public init(persistence: any AppDataPersisting, secrets: any SecretStoring) {
        self.persistence = persistence
        self.secrets = secrets
    }

    public func loadHosts() async throws -> [Host] {
        try await persistence.load().hosts
    }

    public func credential(for host: Host) async throws -> String? {
        let kind: SecretKind = host.authentication == .password ? .password : .keyPassphrase
        return try await secrets.get(hostID: host.id, kind: kind)
    }

    public func exportPortableArchive(passphrase: String) async throws -> Data {
        let hosts = try await persistence.load().hosts
        var records: [PortableHostRecord] = []
        records.reserveCapacity(hosts.count)
        for host in hosts {
            records.append(
                PortableHostRecord(
                    host: host,
                    password: try await secrets.get(hostID: host.id, kind: .password),
                    keyPassphrase: try await secrets.get(hostID: host.id, kind: .keyPassphrase)
                )
            )
        }
        return try PortableArchiveCodec.encode(
            PortableArchivePayload(exportedAt: Date(), hosts: records),
            passphrase: passphrase
        )
    }

    public func importPortableArchive(_ archive: Data, passphrase: String) async throws -> [Host] {
        let payload = try PortableArchiveCodec.decode(archive, passphrase: passphrase)
        var data = try await persistence.load()
        for record in payload.hosts {
            try record.host.validate()
            if let index = data.hosts.firstIndex(where: { $0.id == record.host.id }) {
                data.hosts[index] = record.host
            } else {
                data.hosts.append(record.host)
            }
        }
        data.hosts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try await persistence.save(data)

        for record in payload.hosts {
            if let password = record.password, !password.isEmpty {
                try await secrets.set(password, hostID: record.host.id, kind: .password)
            } else {
                try await secrets.delete(hostID: record.host.id, kind: .password)
            }
            if let passphrase = record.keyPassphrase, !passphrase.isEmpty {
                try await secrets.set(passphrase, hostID: record.host.id, kind: .keyPassphrase)
            } else {
                try await secrets.delete(hostID: record.host.id, kind: .keyPassphrase)
            }
        }
        return data.hosts
    }

    public func save(host: Host, password: String?, passphrase: String?) async throws -> [Host] {
        try host.validate()
        var data = try await persistence.load()
        if let index = data.hosts.firstIndex(where: { $0.id == host.id }) {
            data.hosts[index] = host
        } else {
            data.hosts.append(host)
        }
        data.hosts.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try await persistence.save(data)

        if let password, !password.isEmpty {
            try await secrets.set(password, hostID: host.id, kind: .password)
        }
        if let passphrase, !passphrase.isEmpty {
            try await secrets.set(passphrase, hostID: host.id, kind: .keyPassphrase)
        }
        if host.authentication == .password {
            try await secrets.delete(hostID: host.id, kind: .keyPassphrase)
        } else {
            try await secrets.delete(hostID: host.id, kind: .password)
        }
        return data.hosts
    }

    public func delete(id: UUID) async throws -> [Host] {
        var data = try await persistence.load()
        data.hosts.removeAll { $0.id == id }
        try await persistence.save(data)
        try await secrets.deleteAll(hostID: id)
        return data.hosts
    }

    public func duplicate(_ host: Host) async throws -> [Host] {
        var copy = host
        copy.id = UUID()
        copy.name = "\(host.name) copia"
        copy.lastConnectedAt = nil
        return try await save(host: copy, password: nil, passphrase: nil)
    }
}
