import SwiftUI

struct SettingsView: View {
    @AppStorage("terminal.fontName") private var fontName = "SF Mono"
    @AppStorage("terminal.fontSize") private var fontSize = 13.0
    @AppStorage("terminal.scrollback") private var scrollback = 10_000
    @AppStorage("terminal.bell") private var bell = true
    @AppStorage("terminal.copyOnSelect") private var copyOnSelect = false

    var body: some View {
        TabView {
            Form { Text("Avvio e comportamento generale saranno ampliati nelle prossime milestone.").foregroundStyle(.secondary) }
                .tabItem { Label("Generali", systemImage: "gear") }
            Form {
                TextField("Font", text: $fontName)
                Stepper("Dimensione: \(fontSize, specifier: "%.0f") pt", value: $fontSize, in: 8...32)
                Stepper("Scrollback: \(scrollback)", value: $scrollback, in: 1_000...100_000, step: 1_000)
                Toggle("Bell", isOn: $bell)
                Toggle("Copia alla selezione", isOn: $copyOnSelect)
            }.padding().tabItem { Label("Terminale", systemImage: "terminal") }
            Form { Text("Timeout, keep-alive e verifica host key saranno disponibili con il trasporto SSH.").foregroundStyle(.secondary) }
                .tabItem { Label("SSH", systemImage: "network") }
            Form { Text("MySSH segue automaticamente l'aspetto di macOS.").foregroundStyle(.secondary) }
                .tabItem { Label("Aspetto", systemImage: "paintbrush") }
            Form { Text("I segreti degli host sono protetti dal Keychain locale e non vengono inclusi nel file dati.").foregroundStyle(.secondary) }
                .tabItem { Label("Sicurezza", systemImage: "lock.shield") }
        }.padding(12)
    }
}
