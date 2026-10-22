import Foundation

/// Called only by the background writer. The storage gate excludes transactions
/// and synchronous replacements until this atomic write has actually finished.
enum DraftFileWriter {
    static func write(_ drafts: [NoteDraft], directory: URL) throws {
        let data = try JSONEncoder().encode(drafts)
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("drafts-v1.json")
        if files.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            do { _ = try JSONDecoder().decode([NoteDraft].self, from: original) }
            catch {
                let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
                try files.createDirectory(at: recovery, withIntermediateDirectories: true)
                try original.write(to: recovery.appendingPathComponent(UUID().uuidString + "-drafts-v1.json"), options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
