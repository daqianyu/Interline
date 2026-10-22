import Foundation
import CryptoKit

/// Catalog writes happen only on library changes. Page turns write a small record.
/// Existing v1 books/bookmarks remain readable; optional anchors migrate lazily.
@MainActor
public final class ReadingStorage {
    public static let shared = ReadingStorage()

    private let booksKey = "interline_saved_books_v1"
    private let preferencesKey = "interline_saved_preferences_v1"
    private let bookmarksKey = "interline_saved_bookmarks_v1"
    private let recordPrefix = "interline_reading_record_v2_"
    public nonisolated let directory: URL
    private struct Catalog: Codable {
        let version: Int
        let books: [Book]
    }
    let defaults: UserDefaults
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    public internal(set) var lastError: String?
    var transactionActive = false
    private(set) var isWritingDrafts = false
    // Injectable boundary for deterministic in-flight/failure tests; production
    // encoding, preservation and file I/O all execute off the main actor.
    var draftWriteOperation: @Sendable ([NoteDraft], URL) async throws -> Void = { drafts, directory in
        try await Task.detached(priority: .utility) {
            try DraftFileWriter.write(drafts, directory: directory)
        }.value
    }

    func saveDraftsInBackground(_ drafts: [NoteDraft]) async -> Bool {
        guard !isWritingDrafts, !transactionActive else {
            lastError = "草稿或资料维护正在保存，请稍后重试"
            return false
        }
        guard permitWrite() else { return false }
        isWritingDrafts = true
        defer { isWritingDrafts = false }
        do {
            try await draftWriteOperation(drafts, directory)
            return true
        } catch {
            lastError = "草稿保存失败，未保存输入仍保留，请重试"
            return false
        }
    }
    func permitWrite() -> Bool {
        guard transactionActive || !FileManager.default.fileExists(atPath: directory.appendingPathComponent("restore-journal-v1.json").path) else {
            lastError = "上次数据操作尚未恢复，请先在数据与存储中重试恢复"
            return false
        }
        return true
    }

    public init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? (defaults === UserDefaults.standard
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Interline", isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent("InterlineTests-" + UUID().uuidString, isDirectory: true))
    }

    public var catalogURL: URL { directory.appendingPathComponent("catalog-v2.json") }

    public nonisolated func contentsURL(bookID: String) -> URL {
        let key = SHA256.hash(data: Data(bookID.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("Contents", isDirectory: true).appendingPathComponent(key + ".json")
    }

    /// Large immutable contents can be staged by an import worker before saving metadata.
    public nonisolated func stageContents(of book: Book, replacing: Bool = false) throws {
        guard !book.chapters.isEmpty else { return }
        let url = contentsURL(bookID: book.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if replacing || !FileManager.default.fileExists(atPath: url.path) {
            try JSONEncoder().encode(book.chapters).write(to: url, options: .atomic)
        }
    }

    public func loadBooks(includeContents: Bool = true) -> [Book] {
        guard recoverInterruptedRestore() else { return [] }
        let saved: [Book]
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            do {
                let catalog = try decoder.decode(Catalog.self, from: Data(contentsOf: catalogURL))
                guard catalog.version == 2 else { throw CocoaError(.coderReadCorrupt) }
                saved = catalog.books.map { metadata in
                    var book = metadata
                    if includeContents {
                        do { book.chapters = try readContents(bookID: book.id); book.contentsUnavailable = false }
                        catch { book.contentsUnavailable = true; lastError = "《\(book.title)》正文无法读取，目录记录已保留" }
                    } else if !FileManager.default.fileExists(atPath: contentsURL(bookID: book.id).path) {
                        book.contentsUnavailable = true
                    }
                    return book
                }
            } catch {
                lastError = "书架数据无法读取，原始文件已保留"
                return []
            }
        } else if defaults.object(forKey: booksKey) != nil {
            guard let legacy: [Book] = load([Book].self, key: booksKey) else { return [] }
            saved = legacy
            _ = saveBooks(legacy) // Preserve v1 data as a recovery source.
        } else {
            saved = SampleBooks.defaultLibrary
            _ = saveBooks(saved)
        }
        return saved.map { saved in
            var book = saved
            if let record = loadRecord(bookID: book.id) {
                book.currentChapterIndex = record.chapterIndex
                book.currentPageIndex = record.pageIndex
                book.readingLocation = record.location
                book.visibleEndOffset = record.visibleEndOffset
                book.lastReadDate = record.lastReadDate
            }
            if let anchor = book.readingLocation,
               let index = book.chapters.firstIndex(where: { $0.id == anchor.chapterID }) {
                book.currentChapterIndex = index
            }
            if !book.chapters.isEmpty && !book.chapters.indices.contains(book.currentChapterIndex) {
                book.currentChapterIndex = 0
                book.currentPageIndex = 0
                book.readingLocation = nil
                book.visibleEndOffset = nil
            }
            return includeContents ? book : book.metadata
        }
    }

    @discardableResult public func saveBooks(_ books: [Book]) -> Bool {
        guard permitWrite() else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try preserveUnreadableFile(at: catalogURL) { data in
                let catalog = try self.decoder.decode(Catalog.self, from: data)
                guard catalog.version == 2 else { throw CocoaError(.coderReadCorrupt) }
            }
            for book in books { try stageContents(of: book) }
            let metadata = books.map { book in
                var value = book
                value.updateChapterSummaries()
                value.chapters = []
                return value
            }
            try encoder.encode(Catalog(version: 2, books: metadata)).write(to: catalogURL, options: .atomic)
            return true
        } catch {
            lastError = "书架保存失败，原有目录未被替换"
            return false
        }
    }

    /// A failed read must never turn the only copy into an empty replacement.
    /// Copy exact bytes first; if backup fails, propagate and refuse the write.
    func preserveUnreadableFile(at url: URL, validate: (Data) throws -> Void) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        do { try validate(data) }
        catch {
            let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            let backup = recovery.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try data.write(to: backup, options: .atomic)
        }
    }

    public func loadAnnotations() -> [ReadingAnnotation] {
        let url = directory.appendingPathComponent("annotations-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try decoder.decode([ReadingAnnotation].self, from: Data(contentsOf: url)).filter {
                $0.utf16Offset >= 0 && $0.utf16Length > 0 && $0.utf16Offset <= Int.max - $0.utf16Length
            }
        }
        catch { lastError = "笔记无法读取，原始文件已保留"; return [] }
    }

    @discardableResult public func saveAnnotations(_ annotations: [ReadingAnnotation]) -> Bool {
        guard permitWrite() else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("annotations-v1.json")
            try preserveUnreadableFile(at: url) { data in
                let saved = try self.decoder.decode([ReadingAnnotation].self, from: data)
                guard saved.allSatisfy({ $0.utf16Offset >= 0 && $0.utf16Length > 0 && $0.utf16Offset <= Int.max - $0.utf16Length }) else {
                    throw CocoaError(.coderReadCorrupt)
                }
            }
            try encoder.encode(annotations).write(to: url, options: .atomic)
            return true
        } catch { lastError = "笔记保存失败，请重试"; return false }
    }

    @discardableResult public func purgeContents(bookID: String) -> Bool {
        guard permitWrite() else { return false }
        do {
            let url = contentsURL(bookID: bookID)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            defaults.removeObject(forKey: recordPrefix + bookID)
            if let legacy = defaults.data(forKey: booksKey), let books = try? decoder.decode([Book].self, from: legacy) {
                defaults.set(try encoder.encode(books.filter { $0.id != bookID }), forKey: booksKey)
            }
            return true
        } catch { lastError = "正文文件未能删除，请重试"; return false }
    }

    public func loadPreferences() -> ReadingPreferences {
        var value = load(ReadingPreferences.self, key: preferencesKey) ?? ReadingPreferences()
        value.fontSize = min(ReadingPreferences.maxFontSize, max(ReadingPreferences.minFontSize, value.fontSize))
        value.lineSpacing = min(20, max(0, value.lineSpacing))
        value.horizontalMargin = min(48, max(12, value.horizontalMargin ?? 24))
        value.paragraphSpacing = min(1.5, max(0, value.paragraphSpacing ?? 0.5))
        value.tapZoneFraction = min(0.4, max(0.15, value.tapZoneFraction ?? 0.25))
        return value
    }

    @discardableResult public func savePreferences(_ preferences: ReadingPreferences) -> Bool {
        save(preferences, key: preferencesKey)
    }

    public func loadBookmarks() -> [Bookmark] {
        load([Bookmark].self, key: bookmarksKey) ?? []
    }

    @discardableResult public func saveBookmarks(_ bookmarks: [Bookmark]) -> Bool {
        save(bookmarks, key: bookmarksKey)
    }

    public func loadRecord(bookID: String) -> ReadingRecord? {
        load(ReadingRecord.self, key: recordPrefix + bookID)
    }

    @discardableResult public func saveRecord(for book: Book) -> Bool {
        save(ReadingRecord(book: book), key: recordPrefix + book.id)
    }

    func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard defaults.object(forKey: key) != nil else { return nil }
        guard let data = defaults.data(forKey: key) else {
            lastError = "本地阅读数据格式异常，原始数据已保留"
            return nil
        }
        do { return try decoder.decode(type, from: data) }
        catch {
            lastError = "部分阅读数据无法读取，原始数据已保留"
            return nil
        }
    }

    /// Retain the original key and property-list value before replacing unreadable
    /// defaults. Data values keep their exact bytes; a failed archive blocks writes.
    private func preserveUnreadableDefaults<Value: Decodable>(_ type: Value.Type, key: String) throws {
        guard let original = defaults.object(forKey: key) else { return }
        if let data = original as? Data {
            do { _ = try decoder.decode(type, from: data); return }
            catch { /* Archive the unreadable value before replacing it. */ }
        }
        let snapshot = try PropertyListSerialization.data(
            fromPropertyList: ["key": key, "value": original], format: .binary, options: 0)
        let recovery = directory.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let url = recovery.appendingPathComponent(UUID().uuidString + "-defaults.plist")
        try snapshot.write(to: url, options: .atomic)
    }

    func save<Value: Codable>(_ value: Value, key: String) -> Bool {
        guard permitWrite() else { return false }
        do {
            let data = try encoder.encode(value)
            try preserveUnreadableDefaults(Value.self, key: key)
            defaults.set(data, forKey: key)
            return true
        } catch {
            lastError = "阅读数据保存失败，原始数据未被覆盖，请重试"
            return false
        }
    }
}
