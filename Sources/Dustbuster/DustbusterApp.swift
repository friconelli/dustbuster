import SwiftUI

@main
struct DustbusterApp: App {
    var body: some Scene {
        WindowGroup("Dustbuster") {
            ContentView()
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Controlla aggiornamenti…") {
                    Task { await Updater.shared.check() }
                }
            }
        }
    }
}
