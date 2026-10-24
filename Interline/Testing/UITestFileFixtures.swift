#if DEBUG
import Foundation
import CryptoKit

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
        // Provider files are shared across isolated libraries; each library has
        // its own catalog, and must never be reset on relaunch.
        if !FileManager.default.fileExists(atPath: directory.path) {
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
        }
        guard !FileManager.default.fileExists(atPath: storage.catalogURL.path) else { return }
        let role = ProcessInfo.processInfo.environment["INTERLINE_UI_BACKUP_ROLE"]
        if role == "source" {
            var book = try TXTImportService.parse(data: Data(contentsOf: directory.appendingPathComponent("q01-utf8.txt")), fileName: "FP05.txt").book
            book.title = "FP05 Backup Source"
            book.currentChapterIndex = 1
            let chapter = book.chapters[1]
            book.readingLocation = ReadingLocation(chapterID: chapter.id, utf16Offset: 0)
            let range = NSRange(location: 0, length: 3)
            let quote = (chapter.readingText as NSString).substring(with: range)
            let note = ReadingAnnotation(bookID: book.id, chapterID: chapter.id, range: range, quote: quote, note: "FP05 retained note")
            let draft = NoteDraft(bookID: book.id, chapterID: chapter.id, range: range, quote: quote, text: "FP05 retained draft")
            guard storage.saveBooks([book]), storage.saveRecord(for: book), storage.saveAnnotations([note]) else { throw CocoaError(.fileWriteUnknown) }
            try DraftFileWriter.write([draft], directory: storage.directory)
        } else {
            guard storage.saveBooks([]) else { throw CocoaError(.fileWriteUnknown) }
            if role == "destination" {
                let name = "Interline-完整备份.interlinebackup"
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let baseline: [String: Any] = ["name": name, "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
                try JSONSerialization.data(withJSONObject: baseline, options: [.sortedKeys]).write(to: directory.appendingPathComponent("backup-source.json"), options: .atomic)
            }
        }
    }
}
#endif
