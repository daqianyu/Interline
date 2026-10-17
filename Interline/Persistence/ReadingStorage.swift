import Foundation

// MARK: - Reading Storage (UserDefaults Persistence)
// Adheres to AGENTS.md Section 7 (Separate views, models, state, persistence).

@MainActor
public final class ReadingStorage: Sendable {
    public static let shared = ReadingStorage()

    private let booksKey = "interline_saved_books_v1"
    private let preferencesKey = "interline_saved_preferences_v1"
    private let bookmarksKey = "interline_saved_bookmarks_v1"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func loadBooks() -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: booksKey),
              let decoded = try? decoder.decode([Book].self, from: data),
              !decoded.isEmpty else {
            return SampleBooks.defaultLibrary
        }
        return decoded
    }

    public func saveBooks(_ books: [Book]) {
        if let data = try? encoder.encode(books) {
            UserDefaults.standard.set(data, forKey: booksKey)
        }
    }

    public func loadPreferences() -> ReadingPreferences {
        guard let data = UserDefaults.standard.data(forKey: preferencesKey),
              let decoded = try? decoder.decode(ReadingPreferences.self, from: data) else {
            return ReadingPreferences()
        }
        return decoded
    }

    public func savePreferences(_ preferences: ReadingPreferences) {
        if let data = try? encoder.encode(preferences) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
    }

    public func loadBookmarks() -> [Bookmark] {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey),
              let decoded = try? decoder.decode([Bookmark].self, from: data) else {
            return []
        }
        return decoded
    }

    public func saveBookmarks(_ bookmarks: [Bookmark]) {
        if let data = try? encoder.encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }
}
