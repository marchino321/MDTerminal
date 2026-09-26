import SwiftUI
import UniformTypeIdentifiers

struct PortableArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct PortableTransferView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var archiveDocument = PortableArchiveDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Archivio cifrato") {
                    SecureField("Password archivio", text: $passphrase)
                    SecureField("Ripeti password per esportare", text: $confirmation)
                    Text("Host e credenziali vengono cifrati con AES‑256‑GCM. La password non viene memorizzata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        exportArchive()
                    } label: {
                        Label("Esporta host e password", systemImage: "arrow.up.doc")
                    }
                    .disabled(isWorking || passphrase.isEmpty || passphrase != confirmation)

                    Button {
                        guard !passphrase.isEmpty else { return }
                        isImporting = true
                    } label: {
                        Label("Importa archivio", systemImage: "arrow.down.doc")
                    }
                    .disabled(isWorking || passphrase.isEmpty)
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Trasferimento dati")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: archiveDocument,
            contentType: .json,
            defaultFilename: "MDTerminal-backup.mdterminal"
        ) { result in
            message = result.isSuccess ? "Archivio esportato." : "Esportazione annullata o non riuscita."
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else {
                message = "Importazione annullata o non riuscita."
                return
            }
            importArchive(from: url)
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func exportArchive() {
        guard passphrase == confirmation else { return }
        isWorking = true
        Task {
            if let data = await model.exportPortableArchive(passphrase: passphrase) {
                archiveDocument = PortableArchiveDocument(data: data)
                isExporting = true
            }
            isWorking = false
        }
    }

    private func importArchive(from url: URL) {
        isWorking = true
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                message = await model.importPortableArchive(data, passphrase: passphrase)
                    ? "Host e password importati."
                    : "Importazione non riuscita."
            } catch {
                model.errorMessage = error.localizedDescription
                message = "Importazione non riuscita."
            }
            isWorking = false
        }
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
