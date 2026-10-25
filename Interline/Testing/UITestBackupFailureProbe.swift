#if DEBUG
import Foundation

/// Read-only observations of the real storage and temporary files. Never repairs
/// data or removes workspaces; only the isolated FP06 test role can write reports.
@MainActor
enum UITestBackupFailureProbe {
    static var enabled: Bool {
        UITestFileFixtures.directory != nil &&
        ProcessInfo.processInfo.environment["INTERLINE_UI_BACKUP_ROLE"] == "failure-provider"
    }
    static let sourceNames = ["FP06-valid.interlinebackup", "FP06-truncated.interlinebackup",
                              "FP06-badhash.interlinebackup", "FP06-badquote.json"]

    struct Source: Codable { let bytes: Int; let sha256: String }
    struct Snapshot: Codable, Equatable {
        let files: [String: String]
        let defaults: [String: String]
        let memory: [String: String]
        let counts: [String: Int]
    }
    struct Event: Codable { let name: String; let snapshot: Snapshot; let workspaces: [String] }
    struct Report: Codable {
        let library: String
        let baseline: Snapshot
        let sources: [String: Source]
        var events: [Event]
    }

    static func prepare(book: Book, mark: Bookmark, note: ReadingAnnotation,
                        draft: NoteDraft, preferences: ReadingPreferences, storage: ReadingStorage) throws {
        guard enabled, let directory = UITestFileFixtures.directory else { return }
        let exported = try BackupContainer.export(books: [book], removedBooks: [], preferences: preferences,
            bookmarks: [mark], annotations: [note], drafts: [draft], contentsURL: { storage.contentsURL(bookID: $0) })
        let bytes = try Data(contentsOf: exported.url)
        try bytes.write(to: directory.appendingPathComponent(sourceNames[0]), options: .atomic)
        try Data(bytes.dropLast()).write(to: directory.appendingPathComponent(sourceNames[1]), options: .atomic)
        var wrongHash = bytes
        wrongHash[wrongHash.count - 1] ^= 1
        try wrongHash.write(to: directory.appendingPathComponent(sourceNames[2]), options: .atomic)
        let legacy = try V1BackupWriter.encode(books: [book], removedBooks: [], preferences: preferences,
            bookmarks: [mark], annotations: [note], drafts: [draft], contentsURL: { storage.contentsURL(bookID: $0) })
        guard var object = try JSONSerialization.jsonObject(with: legacy) as? [String: Any],
              var notes = object["annotations"] as? [[String: Any]], notes.count == 1 else {
            throw CocoaError(.coderReadCorrupt)
        }
        notes[0]["quote"] = "FP06 deliberately mismatched quote"
        object["annotations"] = notes
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent(sourceNames[3]), options: .atomic)
    }

    private static func fileHashes(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        for case let url as URL in entries {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(url.path.dropFirst(root.path.count + 1))] = BackupContainer.digest(try Data(contentsOf: url))
            }
        }
        return result
    }

    private static func snapshot(_ state: AppState) throws -> Snapshot {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func hash<T: Encodable>(_ value: T) throws -> String { BackupContainer.digest(try encoder.encode(value)) }
        var defaults: [String: String] = [:]
        for (key, value) in state.storage.defaults.dictionaryRepresentation() where key.hasPrefix("interline_") {
            let data: Data
            if let raw = value as? Data { data = raw }
            else { data = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0) }
            defaults[key] = BackupContainer.digest(data)
        }
        return try Snapshot(files: fileHashes(state.storage.directory), defaults: defaults,
            memory: ["books": hash(state.books.map(\.metadata)), "preferences": hash(state.preferences),
                     "bookmarks": hash(state.bookmarks), "annotations": hash(state.annotations),
                     "drafts": hash(state.drafts), "maintenance": hash(state.maintenance)],
            counts: ["books": state.books.count, "bookmarks": state.bookmarks.count,
                     "annotations": state.annotations.count, "drafts": state.drafts.count])
    }

    private static func workspaces() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("InterlineBackup-") }.sorted()
    }

    static func recordCancellation(state: AppState) async throws -> String {
        guard enabled else { return "" }
        // SwiftUI may retain the old State value until the dismissal transaction
        // settles. Observe a bounded release window; never delete the workspace.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while try !workspaces().isEmpty && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return try record("cancelled", state: state)
    }

    static func record(_ name: String, state: AppState) throws -> String {
        guard enabled, let directory = UITestFileFixtures.directory else { return "" }
        let reportURL = directory.appendingPathComponent("fp06-evidence.json")
        let current = try snapshot(state)
        var report: Report
        if FileManager.default.fileExists(atPath: reportURL.path) {
            report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: reportURL))
        } else {
            var sources: [String: Source] = [:]
            for name in sourceNames {
                let bytes = try Data(contentsOf: directory.appendingPathComponent(name))
                sources[name] = Source(bytes: bytes.count, sha256: BackupContainer.digest(bytes))
            }
            report = Report(library: state.storage.directory.lastPathComponent, baseline: current, sources: sources, events: [])
        }
        let workspaces = try workspaces()
        report.events.append(Event(name: name, snapshot: current, workspaces: workspaces))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        return "\(name)|unchanged=\(current == report.baseline)|workspaces=\(workspaces.count)"
    }
}
#endif
