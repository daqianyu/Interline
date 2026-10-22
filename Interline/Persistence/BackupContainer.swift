import Foundation
import CryptoKit

struct BackupManifest: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let bookID: String
        let byteCount: Int
        let sha256: String
    }
    var version = 2
    var complete = true
    let createdAt: Date
    var books: [Book]
    var removedBooks: [Book]
    let preferences: ReadingPreferences
    let bookmarks: [Bookmark]
    let annotations: [ReadingAnnotation]
    let drafts: [NoteDraft]
    var entries: [Entry]

    var metadata: LibraryBackup {
        LibraryBackup(version: 1, createdAt: createdAt, books: books, removedBooks: removedBooks,
                      preferences: preferences, bookmarks: bookmarks, annotations: annotations, drafts: drafts)
    }
}

enum BackupContainer {
    static let magic = Data("InterlineBackup2\n".utf8)
    static let maximumManifestBytes = 32 * 1_024 * 1_024
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func export(books: [Book], removedBooks: [Book], preferences: ReadingPreferences,
                       bookmarks: [Bookmark], annotations: [ReadingAnnotation], drafts: [NoteDraft],
                       createdAt: Date = Date(),
                       maximumBytes: Int = ReadingStorage.maximumBackupBytes,
                       temporaryParent: URL = FileManager.default.temporaryDirectory,
                       contentsURL: (String) -> URL) throws -> BackupExport {
        try Task.checkCancellation()
        guard maximumBytes >= magic.count + 8, maximumBytes <= ReadingStorage.maximumBackupBytes else {
            throw LibraryBackupError.tooLarge
        }
        let all = books + removedBooks
        let ids = try BackupValidation.bookIDs(all)
        let marks = bookmarks.filter { ids.contains($0.bookId) }
        let notes = annotations.filter { ids.contains($0.bookID) }
        let savedDrafts = drafts.filter { ids.contains($0.bookID) }
        try BackupValidation.references(bookIDs: ids, bookmarks: marks, annotations: notes, drafts: savedDrafts)
        // Check all disk sources before loading the first body.
        var sourceRemaining = maximumBytes
        for book in all {
            try Task.checkCancellation()
            let count: Int
            if book.chapters.isEmpty { count = try BoundedBackupInput.fileSize(contentsURL(book.id)) }
            else {
                var remaining = sourceRemaining
                for chapter in book.chapters {
                    for text in [chapter.id, chapter.title] + chapter.content {
                        guard text.utf8.count <= remaining else { throw LibraryBackupError.tooLarge }
                        remaining -= text.utf8.count
                    }
                }
                count = sourceRemaining - remaining
            }
            guard count <= sourceRemaining else { throw LibraryBackupError.tooLarge }
            sourceRemaining -= count
        }
        let workspace = try BackupWorkspace(parent: temporaryParent)
        let notesByBook = Dictionary(grouping: notes, by: \.bookID)
        let draftsByBook = Dictionary(grouping: savedDrafts, by: \.bookID)
        var headers: [Book] = []
        var entries: [BackupManifest.Entry] = []
        var bodyBytes = 0
        for (index, saved) in all.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                var book = saved
                if book.chapters.isEmpty {
                    book.chapters = try JSONDecoder().decode([Chapter].self,
                        from: BoundedBackupInput.read(contentsURL(book.id), maximumBytes: maximumBytes))
                }
                try BackupValidation.book(book, annotations: notesByBook[book.id] ?? [], drafts: draftsByBook[book.id] ?? [])
                book.contentsUnavailable = false
                let data = try JSONEncoder().encode(book.chapters)
                guard data.count <= maximumBytes - bodyBytes else { throw LibraryBackupError.tooLarge }
                try data.write(to: workspace.bodyURL(index), options: .atomic)
                bodyBytes += data.count
                entries.append(.init(bookID: book.id, byteCount: data.count, sha256: digest(data)))
                headers.append(book.metadata)
            }
        }
        let manifest = BackupManifest(createdAt: createdAt, books: Array(headers.prefix(books.count)),
            removedBooks: Array(headers.dropFirst(books.count)), preferences: preferences, bookmarks: marks,
            annotations: notes, drafts: savedDrafts, entries: entries)
        let manifestData = try JSONEncoder().encode(manifest)
        guard manifestData.count <= maximumManifestBytes,
              manifestData.count <= maximumBytes - magic.count - 8,
              bodyBytes <= maximumBytes - magic.count - 8 - manifestData.count else { throw LibraryBackupError.tooLarge }
        let url = workspace.directory.appendingPathComponent("Interline-完整备份.interlinebackup")
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: magic)
            var length = UInt64(manifestData.count).bigEndian
            try Swift.withUnsafeBytes(of: &length) { try handle.write(contentsOf: Data($0)) }
            try handle.write(contentsOf: manifestData)
            for (index, entry) in entries.enumerated() {
                try copyBody(workspace.bodyURL(index), to: handle, count: entry.byteCount)
                try FileManager.default.removeItem(at: workspace.bodyURL(index))
            }
            try Task.checkCancellation()
            try handle.close()
        } catch { try? handle.close(); throw error }
        return BackupExport(workspace: workspace, url: url)
    }

    static func prepare(url: URL, temporaryParent: URL = FileManager.default.temporaryDirectory) throws -> PreparedLibraryBackup {
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var result: Result<PreparedLibraryBackup, Error>?
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error) { file in
            result = Result { try prepareCoordinated(file, temporaryParent: temporaryParent) }
        }
        if let error { throw error }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private static func prepareCoordinated(_ url: URL, temporaryParent: URL) throws -> PreparedLibraryBackup {
        let size = try BoundedBackupInput.fileSize(url)
        guard size <= ReadingStorage.maximumBackupBytes else { throw LibraryBackupError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: magic.count) ?? Data()
        guard prefix == magic else {
            return try prepareLegacy(BoundedBackupInput.read(url, maximumBytes: ReadingStorage.maximumBackupBytes), temporaryParent: temporaryParent)
        }
        let lengthBytes = try readExact(handle, count: 8)
        let length = lengthBytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length > 0, length <= UInt64(maximumManifestBytes), size >= magic.count + 8,
              length <= UInt64(size - magic.count - 8) else { throw CocoaError(.fileReadCorruptFile) }
        let manifestData = try readExact(handle, count: Int(length))
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
        let all = manifest.books + manifest.removedBooks
        let ids = try BackupValidation.bookIDs(all)
        guard manifest.version == 2, manifest.complete, all.allSatisfy({ $0.chapters.isEmpty }),
              manifest.entries.map(\.bookID) == all.map(\.id) else { throw CocoaError(.coderReadCorrupt) }
        try BackupValidation.references(bookIDs: ids, bookmarks: manifest.bookmarks,
                                        annotations: manifest.annotations, drafts: manifest.drafts)
        var remaining = size - magic.count - 8 - Int(length)
        for entry in manifest.entries {
            guard entry.byteCount > 0, entry.byteCount <= remaining,
                  entry.sha256.count == 64, entry.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            remaining -= entry.byteCount
        }
        guard remaining == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let workspace = try BackupWorkspace(parent: temporaryParent)
        let notes = Dictionary(grouping: manifest.annotations, by: \.bookID)
        let drafts = Dictionary(grouping: manifest.drafts, by: \.bookID)
        var normalizedHeaders: [Book] = []
        for (index, header) in all.enumerated() {
            try autoreleasepool {
                let entry = manifest.entries[index]
                let data = try readExact(handle, count: entry.byteCount)
                guard digest(data) == entry.sha256 else { throw CocoaError(.fileReadCorruptFile) }
                var book = header
                book.chapters = try JSONDecoder().decode([Chapter].self, from: data)
                try BackupValidation.book(book, annotations: notes[book.id] ?? [], drafts: drafts[book.id] ?? [])
                try data.write(to: workspace.bodyURL(index), options: .atomic)
                book.contentsUnavailable = false
                normalizedHeaders.append(book.metadata)
            }
        }
        guard (try handle.read(upToCount: 1) ?? Data()).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        var normalized = manifest
        normalized.books = Array(normalizedHeaders.prefix(manifest.books.count))
        normalized.removedBooks = Array(normalizedHeaders.dropFirst(manifest.books.count))
        return PreparedLibraryBackup(workspace: workspace, manifest: normalized)
    }

    static func prepareLegacy(_ data: Data, temporaryParent: URL = FileManager.default.temporaryDirectory) throws -> PreparedLibraryBackup {
        let backup = try ReadingStorage.decodeBackup(data)
        let workspace = try BackupWorkspace(parent: temporaryParent)
        var entries: [BackupManifest.Entry] = []
        for (index, book) in (backup.books + backup.removedBooks).enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let bytes = try JSONEncoder().encode(book.chapters)
                guard bytes.count <= ReadingStorage.maximumBackupBytes else { throw LibraryBackupError.tooLarge }
                try bytes.write(to: workspace.bodyURL(index), options: .atomic)
                entries.append(.init(bookID: book.id, byteCount: bytes.count, sha256: digest(bytes)))
            }
        }
        let manifest = BackupManifest(createdAt: backup.createdAt, books: backup.books.map(\.metadata),
            removedBooks: backup.removedBooks.map(\.metadata), preferences: backup.preferences, bookmarks: backup.bookmarks,
            annotations: backup.annotations, drafts: backup.drafts, entries: entries)
        return PreparedLibraryBackup(workspace: workspace, manifest: manifest)
    }

    static func readExact(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0, count <= ReadingStorage.maximumBackupBytes else { throw LibraryBackupError.tooLarge }
        var data = Data()
        while data.count < count {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: min(64 * 1_024, count - data.count)) ?? Data()
            guard !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            data.append(chunk)
        }
        return data
    }

    private static func copyBody(_ url: URL, to output: FileHandle, count: Int) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var remaining = count
        while remaining > 0 {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
            guard !chunk.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            try output.write(contentsOf: chunk)
            remaining -= chunk.count
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    }
}
