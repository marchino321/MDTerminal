import Foundation

public struct Host: Identifiable, Codable, Hashable, Sendable {
    public enum Authentication: String, Codable, CaseIterable, Sendable {
        case password
        case privateKey

        public var title: String {
            switch self {
            case .password: "Password"
            case .privateKey: "Chiave SSH"
            }
        }
    }

    public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authentication: Authentication
    public var identityFile: String?
    public var group: String?
    public var tags: [String]
    public var notes: String
    public var colorHex: String?
    public var symbolName: String?
    public var isFavorite: Bool
    public var lastConnectedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authentication: Authentication = .password,
        identityFile: String? = nil,
        group: String? = nil,
        tags: [String] = [],
        notes: String = "",
        colorHex: String? = nil,
        symbolName: String? = nil,
        isFavorite: Bool = false,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authentication = authentication
        self.identityFile = identityFile
        self.group = group
        self.tags = tags
        self.notes = notes
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
    }

    public var endpoint: String { "\(username)@\(hostname):\(port)" }
}

public extension Host {
    static var empty: Host {
        Host(name: "", hostname: "", username: ProcessInfo.processInfo.environment["USER"] ?? "utente")
    }
}
