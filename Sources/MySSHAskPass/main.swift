import Foundation
import AppKit
import MySSHCore

guard let rawID = ProcessInfo.processInfo.environment["MYSSH_HOST_ID"],
      let hostID = UUID(uuidString: rawID) else {
    exit(1)
}

let rawPrompt = CommandLine.arguments.dropFirst().joined(separator: " ")
let prompt = rawPrompt.lowercased()

if prompt.contains("authenticity") || prompt.contains("continue connecting") || prompt.contains("yes/no") {
    NSApplication.shared.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Verifica chiave host"
    alert.informativeText = rawPrompt
    alert.addButton(withTitle: "Considera attendibile")
    alert.addButton(withTitle: "Annulla")
    NSApp.activate(ignoringOtherApps: true)
    let answer = alert.runModal() == .alertFirstButtonReturn ? "yes\n" : "no\n"
    FileHandle.standardOutput.write(Data(answer.utf8))
    exit(answer.hasPrefix("yes") ? 0 : 1)
}

let kind: SecretKind = prompt.contains("passphrase") ? .keyPassphrase : .password

do {
    if let secret = try await KeychainStore().get(hostID: hostID, kind: kind) {
        FileHandle.standardOutput.write(Data(secret.utf8))
        FileHandle.standardOutput.write(Data([0x0A]))
        exit(0)
    }
} catch {}

NSApplication.shared.setActivationPolicy(.accessory)
let alert = NSAlert()
alert.messageText = kind == .keyPassphrase ? "Passphrase chiave SSH" : "Password SSH"
alert.informativeText = rawPrompt
let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
alert.accessoryView = field
alert.addButton(withTitle: "Continua")
alert.addButton(withTitle: "Annulla")
NSApp.activate(ignoringOtherApps: true)
guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { exit(1) }
FileHandle.standardOutput.write(Data(field.stringValue.utf8))
FileHandle.standardOutput.write(Data([0x0A]))
exit(0)
