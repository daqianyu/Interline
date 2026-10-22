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
            let name = "InterlineUISmoke-" + (ProcessInfo.processInfo.environment["INTERLINE_UI_TEST_SUITE"] ?? UUID().uuidString)
            let defaults = UserDefaults(suiteName: name)!
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            if ProcessInfo.processInfo.environment["INTERLINE_UI_FAIL_NOTE_SAVE"] == "1" {
                try? FileManager.default.createDirectory(at: directory.appendingPathComponent("annotations-v1.json"), withIntermediateDirectories: true)
            }
            if ProcessInfo.processInfo.environment["INTERLINE_UI_FAIL_DRAFT_SAVE"] == "1" {
                try? FileManager.default.createDirectory(at: directory.appendingPathComponent("drafts-v1.json"), withIntermediateDirectories: true)
            }
            let state = AppState(storage: ReadingStorage(defaults: defaults, directory: directory), loadsContentsOnDemand: true)
            if ProcessInfo.processInfo.environment["INTERLINE_UI_DELAY_CONTENTS"] == "1" {
                state.contentsLoader = BookContentsLoader(beforeRead: { try? await Task.sleep(for: .seconds(30)) })
            }
            // Use the app's real appearance preference in isolated UI tests;
            // AppleInterfaceStyle launch defaults do not reliably change UIKit.
            if ProcessInfo.processInfo.environment["INTERLINE_UI_DARK_APPEARANCE"] == "1" {
                state.preferences.followsSystemAppearance = false
                state.preferences.isDarkMode = true
            }
            _appState = StateObject(wrappedValue: state)
            return
        }
        #endif
        _appState = StateObject(wrappedValue: AppState(loadsContentsOnDemand: true))
    }

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in appState.handleMemoryWarning() }
        }
    }
}

