import Foundation
import XCTest
@testable import MySSHCore

final class KeychainTests: XCTestCase {
    func testSetGetDelete() async throws {
        let store = KeychainStore(service: "com.myssh.tests.\(UUID().uuidString)")
        let hostID = UUID()
        try await store.set("correct horse battery staple", hostID: hostID, kind: .password)
        let value = try await store.get(hostID: hostID, kind: .password)
        XCTAssertEqual(value, "correct horse battery staple")
        try await store.deleteAll(hostID: hostID)
        let deleted = try await store.get(hostID: hostID, kind: .password)
        XCTAssertNil(deleted)
    }
}
