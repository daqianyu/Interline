import SwiftUI

// MARK: - Interline Application Entry Point
// AGENTS.md Section 1 (Native iOS Novel Reader).

@main
struct InterlineApp: App {
    @StateObject private var appState: AppState

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["INTERLINE_UI_TESTING"] == "1" {
            // UI smoke tests never read or reset a person's actual library.
            let name = "InterlineUISmoke-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            _appState = StateObject(wrappedValue: AppState(storage: ReadingStorage(defaults: defaults, directory: directory)))
            return
        }
        #endif
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(appState)
        }
    }
}

