#if os(iOS)
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public final class IOSSSHClient: @unchecked Sendable {
    public enum ClientError: LocalizedError {
        case missingPassword
        case closed

        public var errorDescription: String? {
            switch self {
            case .missingPassword: "Password SSH non disponibile su questo iPad."
            case .closed: "La sessione SSH è chiusa."
            }
        }
    }

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var connection: Channel?
    private var shell: Channel?

    public init() {}

    deinit { try? group.syncShutdownGracefully() }

    public func connect(
        host: String,
        port: Int,
        username: String,
        password: String,
        output: @escaping @Sendable (String) -> Void
    ) async throws {
        let authentication = PasswordAuthentication(username: username, password: password)
        let serverAuthentication = AcceptFirstHostKey()
        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(
                    NIOSSHHandler(
                        role: .client(.init(userAuthDelegate: authentication, serverAuthDelegate: serverAuthentication)),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                )
            }

        let channel = try await bootstrap.connect(host: host, port: port).get()
        connection = channel
        let promise = channel.eventLoop.makePromise(of: Channel.self)
        channel.eventLoop.execute {
            do {
                let ssh = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                ssh.createChannel(promise, channelType: .session) { child, _ in
                    child.pipeline.addHandler(RemoteOutputHandler(output: output))
                }
            } catch {
                promise.fail(error)
            }
        }
        let shell = try await promise.futureResult.get()
        self.shell = shell
        try await shell.triggerUserOutboundEvent(
            SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: 100,
                terminalRowHeight: 30,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: .init([:])
            )
        )
        try await shell.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true))
    }

    public func send(_ text: String) async throws {
        guard let shell else { throw ClientError.closed }
        var buffer = shell.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        try await shell.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)))
    }

    public func disconnect() async {
        try? await shell?.close()
        try? await connection?.close()
        shell = nil; connection = nil
    }
}

private final class PasswordAuthentication: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private var attempted = false
    private let username: String
    private let password: String
    init(username: String, password: String) { self.username = username; self.password = password }
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !attempted, availableMethods.contains(.password) else { return nextChallengePromise.succeed(nil) }
        attempted = true
        nextChallengePromise.succeed(.init(username: username, serviceName: "ssh-connection", offer: .password(.init(password: password))))
    }
}

private final class AcceptFirstHostKey: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) { validationCompletePromise.succeed(()) }
}

private final class RemoteOutputHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    private let output: @Sendable (String) -> Void
    init(output: @escaping @Sendable (String) -> Void) { self.output = output }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var data = unwrapInboundIn(data)
        guard case .byteBuffer(var buffer) = data.data, let text = buffer.readString(length: buffer.readableBytes) else { return }
        output(text)
    }
}
#endif
