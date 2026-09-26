import SwiftUI
import MySSHCore

@main
struct MySSHApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
#if os(macOS)
                .frame(minWidth: 900, minHeight: 580)
#else
                .preferredColorScheme(.dark)
#endif
                .task { await model.load() }
        }
#if os(macOS)
        .windowStyle(.titleBar)
#endif
        .commands {
            CommandGroup(after: .newItem) {
                Button("Nuovo host…") { model.createHost() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

#if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 620, height: 440)
        }
#endif
    }
}
