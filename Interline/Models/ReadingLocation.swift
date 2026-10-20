import Foundation

/// UTF-16 offsets in Chapter.readingText, matching Core Text. Pages are derived.
public struct ReadingLocation: Codable, Sendable, Hashable {
    public let chapterID: String
    public let utf16Offset: Int

    public init(chapterID: String, utf16Offset: Int) {
        self.chapterID = chapterID
        self.utf16Offset = max(0, utf16Offset)
    }
}

public struct ReadingRecord: Codable, Sendable {
    public let chapterIndex: Int
    public let pageIndex: Int
    public let location: ReadingLocation?
    public let visibleEndOffset: Int?
    public let lastReadDate: Date

    public init(book: Book) {
        chapterIndex = book.currentChapterIndex
        pageIndex = book.currentPageIndex
        location = book.readingLocation
        visibleEndOffset = book.visibleEndOffset
        lastReadDate = book.lastReadDate
    }
}
