import CryptoKit
import Foundation
import Security

public enum PortableArchiveError: LocalizedError, Equatable {
    case emptyPassphrase
    case invalidArchive
    case unsupportedVersion
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .emptyPassphrase: "Inserisci una password per proteggere l'archivio."
        case .invalidArchive: "Il file non è un archivio MD Terminal valido."
        case .unsupportedVersion: "Questa versione dell'archivio non è supportata."
        case .decryptionFailed: "Password errata oppure archivio danneggiato."
        }
    }
}

struct PortableHostRecord: Codable, Sendable {
    let host: Host
    let password: String?
    let keyPassphrase: String?
}

struct PortableArchivePayload: Codable, Sendable {
    let exportedAt: Date
    let hosts: [PortableHostRecord]
}

private struct PortableArchiveEnvelope: Codable {
    let format: String
    let version: Int
    let algorithm: String
    let iterations: Int
    let salt: Data
    let ciphertext: Data
}

enum PortableArchiveCodec {
    private static let format = "com.mdterminal.portable-archive"
    private static let version = 1
    private static let iterations = 100_000

    static func encode(_ payload: PortableArchivePayload, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else { throw PortableArchiveError.emptyPassphrase }
        let salt = randomData(count: 16)
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let plaintext = try encoder.encode(payload)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw PortableArchiveError.invalidArchive }
        return try encoder.encode(
            PortableArchiveEnvelope(
                format: format,
                version: version,
                algorithm: "AES-256-GCM/SHA-256-KDF",
                iterations: iterations,
                salt: salt,
                ciphertext: combined
            )
        )
    }

    static func decode(_ data: Data, passphrase: String) throws -> PortableArchivePayload {
        guard !passphrase.isEmpty else { throw PortableArchiveError.emptyPassphrase }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(PortableArchiveEnvelope.self, from: data),
              envelope.format == format else { throw PortableArchiveError.invalidArchive }
        guard envelope.version == version else { throw PortableArchiveError.unsupportedVersion }
        let key = deriveKey(passphrase: passphrase, salt: envelope.salt, iterations: envelope.iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            let plaintext = try AES.GCM.open(box, using: key)
            return try decoder.decode(PortableArchivePayload.self, from: plaintext)
        } catch {
            throw PortableArchiveError.decryptionFailed
        }
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        let password = Data(passphrase.utf8)
        var input = password
        input.append(salt)
        var digest = Data(SHA256.hash(data: input))
        for _ in 1..<max(1, iterations) {
            input = digest
            input.append(password)
            input.append(salt)
            digest = Data(SHA256.hash(data: input))
        }
        return SymmetricKey(data: digest)
    }

    private static func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}
