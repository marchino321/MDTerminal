import XCTest
@testable import MySSHCore

final class OpenSSHCommandBuilderTests: XCTestCase {
    func testPasswordCommandDoesNotExposeSecret() throws {
        let host = MySSHCore.Host(name: "Prod", hostname: "example.com", username: "deploy")
        let secret = "test-password-that-must-not-leak"
        let command = try OpenSSHCommandBuilder().make(host: host, askPassPath: "/tmp/askpass")
        XCTAssertEqual(command.executable, "/usr/bin/ssh")
        XCTAssertTrue(command.arguments.contains("deploy@example.com"))
        XCTAssertTrue(command.arguments.contains("StrictHostKeyChecking=ask"))
        XCTAssertFalse(command.arguments.joined().contains(secret))
        XCTAssertFalse(command.environment.joined().contains(secret))
        XCTAssertTrue(command.environment.contains("MYSSH_HOST_ID=\(host.id.uuidString)"))
    }

    func testSFTPUsesSFTPExecutable() throws {
        let host = MySSHCore.Host(name: "Prod", hostname: "example.com", username: "deploy")
        XCTAssertEqual(try OpenSSHCommandBuilder().make(host: host, mode: .sftp, askPassPath: nil).executable, "/usr/bin/sftp")
    }
}
