import Foundation

public enum SSHLaunchMode: Sendable {
    case shell
    case sftp
    case localForward(localPort: Int, remoteHost: String, remotePort: Int)
    case remoteForward(remotePort: Int, localHost: String, localPort: Int)
    case dynamicForward(localPort: Int)
}

public struct SSHLaunchConfiguration: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String]

    public init(executable: String, arguments: [String], environment: [String]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public struct OpenSSHCommandBuilder: Sendable {
    public init() {}

    public func make(
        host: Host,
        mode: SSHLaunchMode = .shell,
        askPassPath: String?,
        connectTimeout: Int = 15,
        keepAliveInterval: Int = 30
    ) throws -> SSHLaunchConfiguration {
        try host.validate()
        let executable = mode.isSFTP ? "/usr/bin/sftp" : "/usr/bin/ssh"
        var arguments = [
            "-o", "Port=\(host.port)",
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "ServerAliveInterval=\(keepAliveInterval)",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=ask",
            "-o", "UpdateHostKeys=ask"
        ]

        switch host.authentication {
        case .password:
            arguments += ["-o", "PreferredAuthentications=keyboard-interactive,password", "-o", "PubkeyAuthentication=no"]
        case .privateKey:
            if let identityFile = host.identityFile { arguments += ["-i", NSString(string: identityFile).expandingTildeInPath] }
            arguments += ["-o", "IdentitiesOnly=yes"]
        }

        switch mode {
        case .shell, .sftp:
            break
        case let .localForward(localPort, remoteHost, remotePort):
            arguments += ["-N", "-L", "\(localPort):\(remoteHost):\(remotePort)"]
        case let .remoteForward(remotePort, localHost, localPort):
            arguments += ["-N", "-R", "\(remotePort):\(localHost):\(localPort)"]
        case let .dynamicForward(localPort):
            arguments += ["-N", "-D", String(localPort)]
        }
        arguments.append("\(host.username)@\(host.hostname)")

        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.removeAll { $0.hasPrefix("SSH_ASKPASS=") || $0.hasPrefix("MYSSH_HOST_ID=") }
        if let askPassPath {
            environment += [
                "SSH_ASKPASS=\(askPassPath)",
                "SSH_ASKPASS_REQUIRE=force",
                "MYSSH_HOST_ID=\(host.id.uuidString)"
            ]
        }
        environment += ["TERM=xterm-256color", "LANG=\(Locale.current.identifier).UTF-8"]
        return SSHLaunchConfiguration(executable: executable, arguments: arguments, environment: environment)
    }
}

private extension SSHLaunchMode {
    var isSFTP: Bool {
        if case .sftp = self { return true }
        return false
    }
}
