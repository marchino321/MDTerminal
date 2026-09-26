import XCTest
@testable import MySSHCore

final class SSHConfigParserTests: XCTestCase {
    func testParsesSupportedFieldsAndSkipsWildcard() {
        let config = """
        Host *
          ServerAliveInterval 30
        Host production prod
          HostName 10.0.0.8
          User deploy
          Port 2222
          IdentityFile ~/.ssh/id_ed25519
        """
        let hosts = SSHConfigParser().parse(config, defaultUsername: "fallback")
        XCTAssertEqual(hosts.count, 2)
        XCTAssertEqual(hosts[0].hostname, "10.0.0.8")
        XCTAssertEqual(hosts[0].port, 2222)
        XCTAssertEqual(hosts[0].username, "deploy")
        XCTAssertEqual(hosts[0].authentication, .privateKey)
    }
}
