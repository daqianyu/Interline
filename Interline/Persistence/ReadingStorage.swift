import Foundation

/// Catalog writes happen only on library changes. Page turns write a small record.
/// Existing v1 books/bookmarks remain readable; optional anchors migrate lazily.
@MainActor
public final class ReadingStorage {
    public static let shared = ReadingStorage()

    private let booksKey = "interline_saved_books_v1"
    private let preferencesKey = "interline_saved_preferences_v1"
    private let bookmarksKey = "interline_saved_bookmarks_v1"
    private let recordPrefix = "interline_reading_record_v2_"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public private(set) var lastError: String?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadBooks() -> [Book] {
        // An explicitly saved empty array is a valid, intentionally empty shelf.
        guard defaults.object(forKey: booksKey) != nil else {
            let samples = SampleBooks.defaultLibrary
            _ = saveBooks(samples)
            return samples
        }
        guard let books: [Book] = load([Book].self, key: booksKey) else { return [] }
        return books.map { saved in
            var book = saved
            if let record = loadRecord(bookID: book.id) {
                book.currentChapterIndex = record.chapterIndex
                book.currentPageIndex = record.pageIndex
                book.readingLocation = record.location
                book.visibleEndOffset = record.visibleEndOffset
                book.lastReadDate = record.lastReadDate
            }
            // Prefer stable chapter IDs over mutable array positions.
            if let anchor = book.readingLocation,
               let index = book.chapters.firstIndex(where: { $0.id == anchor.chapterID }) {
                book.currentChapterIndex = index
            }
            if !book.chapters.indices.contains(book.currentChapterIndex) {
                book.currentChapterIndex = 0
                book.currentPageIndex = 0
                book.readingLocation = nil
                book.visibleEndOffset = nil
            }
            return book
        }
    }

    @discardableResult public func saveBooks(_ books: [Book]) -> Bool {
        save(books, key: booksKey)
    }

    public func loadPreferences() -> ReadingPreferences {
        var value = load(ReadingPreferences.self, key: preferencesKey) ?? ReadingPreferences()
        value.fontSize = min(ReadingPreferences.maxFontSize, max(ReadingPreferences.minFontSize, value.fontSize))
        value.lineSpacing = min(20, max(0, value.lineSpacing))
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

    private func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
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

    private func save<Value: Encodable>(_ value: Value, key: String) -> Bool {
        do {
            defaults.set(try encoder.encode(value), forKey: key)
            return true
        } catch {
            lastError = "阅读数据保存失败，请重试"
            return false
        }
    }
}
