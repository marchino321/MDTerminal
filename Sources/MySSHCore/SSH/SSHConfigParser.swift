import Foundation

public struct SSHConfigParser: Sendable {
    public init() {}

    public func parse(_ contents: String, defaultUsername: String = ProcessInfo.processInfo.environment["USER"] ?? "utente") -> [Host] {
        struct Entry {
            var aliases: [String]
            var hostname: String?
            var user: String?
            var port: Int?
            var identityFile: String?
        }

        var entries: [Entry] = []
        var current: Entry?
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { continue }
            let components = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard components.count == 2 else { continue }
            let key = components[0].lowercased()
            let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "host" {
                if let current { entries.append(current) }
                current = Entry(aliases: value.split(whereSeparator: { $0.isWhitespace }).map(String.init))
                continue
            }
            guard current != nil else { continue }
            switch key {
            case "hostname": current?.hostname = unquote(value)
            case "user": current?.user = unquote(value)
            case "port": current?.port = Int(value)
            case "identityfile": current?.identityFile = NSString(string: unquote(value)).expandingTildeInPath
            default: break
            }
        }
        if let current { entries.append(current) }

        return entries.flatMap { entry in
            entry.aliases.compactMap { alias in
                guard !alias.contains("*") && !alias.contains("?") && !alias.hasPrefix("!") else { return nil }
                let identity = entry.identityFile
                return Host(
                    name: alias,
                    hostname: entry.hostname ?? alias,
                    port: entry.port ?? 22,
                    username: entry.user ?? defaultUsername,
                    authentication: identity == nil ? .password : .privateKey,
                    identityFile: identity,
                    group: "SSH Config"
                )
            }
        }
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else { return value }
        return String(value.dropFirst().dropLast())
    }
}
