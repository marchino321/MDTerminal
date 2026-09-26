import Foundation
import Security

public enum SecretKind: String, Sendable {
    case password
    case keyPassphrase
}

public protocol SecretStoring: Sendable {
    func set(_ secret: String, hostID: UUID, kind: SecretKind) async throws
    func get(hostID: UUID, kind: SecretKind) async throws -> String?
    func delete(hostID: UUID, kind: SecretKind) async throws
    func deleteAll(hostID: UUID) async throws
}

public enum KeychainError: LocalizedError, Equatable {
    case invalidData
    case unexpectedStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidData: "Il segreto nel Keychain non è valido."
        case .unexpectedStatus(let status): "Errore Keychain (codice \(status))."
        }
    }
}

public actor KeychainStore: SecretStoring {
    private let service: String

    public init(service: String = "com.myssh.credentials") {
        self.service = service
    }

    public func set(_ secret: String, hostID: UUID, kind: SecretKind) throws {
        guard let data = secret.data(using: .utf8) else { throw KeychainError.invalidData }
        let query = baseQuery(hostID: hostID, kind: kind)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func get(hostID: UUID, kind: SecretKind) throws -> String? {
        var query = baseQuery(hostID: hostID, kind: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return value
    }

    public func delete(hostID: UUID, kind: SecretKind) throws {
        let status = SecItemDelete(baseQuery(hostID: hostID, kind: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func deleteAll(hostID: UUID) throws {
        try delete(hostID: hostID, kind: .password)
        try delete(hostID: hostID, kind: .keyPassphrase)
    }

    private func baseQuery(hostID: UUID, kind: SecretKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(hostID.uuidString).\(kind.rawValue)",
            kSecAttrSynchronizable as String: false
        ]
    }
}
