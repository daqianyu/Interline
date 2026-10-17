import SwiftUI

// MARK: - Interline Application Entry Point
// AGENTS.md Section 1 (Native iOS Novel Reader).

@main
struct InterlineApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(appState)
        }
    }
}
