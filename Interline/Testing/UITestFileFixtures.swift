#if DEBUG
import Foundation

/// Only the dedicated provider test build bundles these files and exposes Documents.
/// Normal debug launches and release builds never prepare or read this directory.
@MainActor
enum UITestFileFixtures {
    static var directory: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["INTERLINE_UI_TESTING"] == "1",
              let value = environment["INTERLINE_UI_PROVIDER_SUITE"],
              let id = UUID(uuidString: value) else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InterlineQ01-" + id.uuidString, isDirectory: true)
    }

    static func prepare(storage: ReadingStorage) throws {
        guard let directory else { return }
        // Never reset a suite on relaunch: persistence is part of the test.
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        guard let manifest = Bundle.main.url(forResource: "expected", withExtension: "json"),
              let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
              let files = entries["files"] as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files {
            guard let name = file["name"] as? String, name == (name as NSString).lastPathComponent,
                  let source = Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                               withExtension: (name as NSString).pathExtension) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        }
        try FileManager.default.copyItem(at: manifest, to: directory.appendingPathComponent("expected.json"))
        guard storage.saveBooks([]) else { throw CocoaError(.fileWriteUnknown) }
    }
}
#endif
