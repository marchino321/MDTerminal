import XCTest
@testable import MySSHCore

final class HostTests: XCTestCase {
    func testValidHost() throws {
        let host = MySSHCore.Host(name: "Production", hostname: "prod.example.com", username: "deploy")
        XCTAssertNoThrow(try host.validate())
        XCTAssertEqual(host.endpoint, "deploy@prod.example.com:22")
    }

    func testRejectsInvalidPort() {
        let host = MySSHCore.Host(name: "Production", hostname: "prod.example.com", port: 0, username: "deploy")
        XCTAssertThrowsError(try host.validate()) { XCTAssertEqual($0 as? HostValidationError, .invalidPort) }
    }

    func testPrivateKeyRequiresPath() {
        let host = MySSHCore.Host(name: "Production", hostname: "prod.example.com", username: "deploy", authentication: .privateKey)
        XCTAssertThrowsError(try host.validate()) { XCTAssertEqual($0 as? HostValidationError, .missingIdentityFile) }
    }
}
