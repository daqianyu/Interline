import Foundation

// MARK: - Bookmark Model
public struct Bookmark: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let bookId: String
    public let chapterIndex: Int
    public let chapterTitle: String
    public let pageIndex: Int
    public let snippet: String
    public let location: ReadingLocation?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        chapterIndex: Int,
        chapterTitle: String,
        pageIndex: Int,
        snippet: String,
        createdAt: Date = Date(),
        location: ReadingLocation? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.snippet = snippet
        self.createdAt = createdAt
        self.location = location
    }
}

