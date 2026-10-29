import SwiftUI

@main
struct DustbusterApp: App {
    var body: some Scene {
        WindowGroup("Dustbuster") {
            ContentView()
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
    }
}
