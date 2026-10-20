import Foundation

public struct ReadingAnnotation: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let bookID: String
    public let chapterID: String
    public let utf16Offset: Int
    public let utf16Length: Int
    public let quote: String
    public var note: String
    public let createdAt: Date

    public init(bookID: String, chapterID: String, range: NSRange, quote: String, note: String = "") {
        id = UUID().uuidString
        self.bookID = bookID
        self.chapterID = chapterID
        utf16Offset = range.location
        utf16Length = range.length
        self.quote = quote
        self.note = note
        createdAt = Date()
    }

    public var range: NSRange { NSRange(location: utf16Offset, length: utf16Length) }
    public var location: ReadingLocation { ReadingLocation(chapterID: chapterID, utf16Offset: utf16Offset) }
}
