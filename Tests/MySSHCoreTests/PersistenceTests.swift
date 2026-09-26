import Foundation
import XCTest
@testable import MySSHCore

final class PersistenceTests: XCTestCase {
    func testRoundTripDoesNotContainSecrets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("data.json")
        let store = AppDataStore(fileURL: url)
        let host = MySSHCore.Host(name: "Server", hostname: "10.0.0.1", username: "root")

        try await store.save(AppData(hosts: [host]))
        let loaded = try await store.load()
        let raw = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(loaded.hosts, [host])
        XCTAssertFalse(raw.contains("\"password\" :"))
        XCTAssertFalse(raw.contains("\"passphrase\" :"))
    }
}
