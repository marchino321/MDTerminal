import Foundation

public struct AppData: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var hosts: [Host]

    public init(schemaVersion: Int = 1, hosts: [Host] = []) {
        self.schemaVersion = schemaVersion
        self.hosts = hosts
    }
}

public enum HostValidationError: LocalizedError, Equatable {
    case missingName
    case missingHostname
    case missingUsername
    case invalidPort
    case missingIdentityFile

    public var errorDescription: String? {
        switch self {
        case .missingName: "Inserisci un nome."
        case .missingHostname: "Inserisci hostname o indirizzo IP."
        case .missingUsername: "Inserisci lo username."
        case .invalidPort: "La porta deve essere compresa tra 1 e 65535."
        case .missingIdentityFile: "Seleziona il file della chiave privata."
        }
    }
}

public extension Host {
    func validate() throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw HostValidationError.missingName }
        if hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw HostValidationError.missingHostname }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw HostValidationError.missingUsername }
        if !(1...65_535).contains(port) { throw HostValidationError.invalidPort }
        if authentication == .privateKey,
           (identityFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HostValidationError.missingIdentityFile
        }
    }
}
