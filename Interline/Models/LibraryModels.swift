import Foundation

public enum NoticeAction: Sendable, Equatable { case undoRemoval, retryCleanup }
public struct AppNotice: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let isError: Bool
    public let action: NoticeAction?
}

public struct NoteDraft: Identifiable, Codable, Sendable {
    public var id: String
    public let bookID: String
    public let chapterID: String
    public let range: NSRange
    public let quote: String
    public let annotationID: String?
    public var text: String
    public var updatedAt: Date

    public init(bookID: String, chapterID: String, range: NSRange, quote: String, annotationID: String? = nil, text: String = "") {
        self.id = annotationID.map { "edit-" + $0 } ?? "new-\(bookID)-\(chapterID)-\(range.location)-\(range.length)"
        self.bookID = bookID; self.chapterID = chapterID; self.range = range
        self.quote = quote; self.annotationID = annotationID; self.text = text; updatedAt = Date()
    }
}

public struct PendingDeletion: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: Date
}

public struct LibraryMaintenanceState: Codable, Sendable {
    public var removedBooks: [Book] = []
    public var pendingDeletions: [PendingDeletion] = []
}

public struct LibraryBackup: Codable, Sendable {
    public let version: Int
    public let createdAt: Date
    public var books: [Book]
    public var removedBooks: [Book]
    public var preferences: ReadingPreferences
    public var bookmarks: [Bookmark]
    public var annotations: [ReadingAnnotation]
    public var drafts: [NoteDraft]
}

public struct RecoveryFile: Identifiable, Sendable {
    public let url: URL
    public let date: Date
    public let size: Int
    public var id: String { url.lastPathComponent }
}
