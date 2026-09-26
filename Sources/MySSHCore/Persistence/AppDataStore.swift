import Foundation

public protocol AppDataPersisting: Sendable {
    func load() async throws -> AppData
    func save(_ data: AppData) async throws
}

public actor AppDataStore: AppDataPersisting {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> AppData {
        guard fileManager.fileExists(atPath: fileURL.path) else { return AppData() }
        return try decoder.decode(AppData.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ data: AppData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(data).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("MySSH", isDirectory: true)
            .appendingPathComponent("app-data.json")
    }
}
