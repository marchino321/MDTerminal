import SwiftUI
#if os(macOS)
import AppKit
#endif
import MySSHCore

struct HostEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var host: ServerHost
    @State private var password = ""
    @State private var passphrase = ""
    @State private var tagsText: String
    @State private var isSaving = false

    init(host: ServerHost) {
        _host = State(initialValue: host)
        _tagsText = State(initialValue: host.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Host") {
                    TextField("Nome", text: $host.name)
                    TextField("Hostname o IP", text: $host.hostname)
                    TextField("Username", text: $host.username)
                    TextField("Porta", value: $host.port, format: .number).frame(width: 120)
                }
                Section("Autenticazione") {
                    Picker("Metodo", selection: $host.authentication) {
                        ForEach(ServerHost.Authentication.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    if host.authentication == .password {
                        SecureField("Password (vuota = mantieni quella salvata)", text: $password)
                    } else {
#if os(macOS)
                        HStack {
                            TextField("File chiave privata", text: identityBinding)
                            Button("Scegli…") { chooseIdentityFile() }
                        }
#else
                        TextField("Riferimento chiave privata", text: identityBinding)
#endif
                        SecureField("Passphrase (vuota = mantieni quella salvata)", text: $passphrase)
                    }
                    Text("Password e passphrase vengono salvate esclusivamente nel Keychain del dispositivo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Organizzazione") {
                    TextField("Gruppo", text: optionalBinding(\ServerHost.group))
                    TextField("Tag separati da virgola", text: $tagsText)
                    Toggle("Preferito", isOn: $host.isFavorite)
                }
                Section("Dettagli") {
                    TextField("Note", text: $host.notes, axis: .vertical).lineLimit(3...6)
                    TextField("Icona SF Symbols", text: optionalBinding(\ServerHost.symbolName))
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Annulla", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Salva") { save() }
                    .keyboardShortcut(.defaultAction).disabled(isSaving)
            }.padding()
        }
        .frame(width: 620, height: 620)
    }

    private var identityBinding: Binding<String> {
        Binding(get: { host.identityFile ?? "" }, set: { host.identityFile = $0.isEmpty ? nil : $0 })
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<ServerHost, String?>) -> Binding<String> {
        Binding(get: { host[keyPath: keyPath] ?? "" }, set: { host[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func chooseIdentityFile() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { host.identityFile = panel.url?.path }
#endif
    }

    private func save() {
        host.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        isSaving = true
        Task {
            _ = await model.save(host, password: password.isEmpty ? nil : password, passphrase: passphrase.isEmpty ? nil : passphrase)
            isSaving = false
        }
    }
}
