import Foundation

/// Shared by v1 import and incremental export so a successful export is readable.
enum BackupValidation {
    static func bookIDs(_ books: [Book]) throws -> Set<String> {
        let ids = Set(books.map(\.id))
        guard books.count <= 10_000, ids.count == books.count, !ids.contains("") else {
            throw CocoaError(.coderReadCorrupt)
        }
        return ids
    }

    static func references(bookIDs: Set<String>, bookmarks: [Bookmark],
                           annotations: [ReadingAnnotation], drafts: [NoteDraft]) throws {
        guard Set(bookmarks.map(\.id)).count == bookmarks.count,
              Set(annotations.map(\.id)).count == annotations.count,
              Set(drafts.map(\.id)).count == drafts.count,
              bookmarks.allSatisfy({ bookIDs.contains($0.bookId) }),
              annotations.allSatisfy({ bookIDs.contains($0.bookID) }),
              drafts.allSatisfy({ bookIDs.contains($0.bookID) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
    }

    static func book(_ book: Book, annotations: [ReadingAnnotation], drafts: [NoteDraft]) throws {
        guard !book.chapters.isEmpty,
              Set(book.chapters.map(\.id)).count == book.chapters.count else {
            throw CocoaError(.coderReadCorrupt)
        }
        var remaining = 24 * 1_024 * 1_024
        for chapter in book.chapters {
            try Task.checkCancellation()
            guard chapter.readingLength <= remaining else { throw CocoaError(.coderReadCorrupt) }
            remaining -= chapter.readingLength
        }
        let chapters = Dictionary(uniqueKeysWithValues: book.chapters.map { ($0.id, $0) })
        func valid(chapterID: String, range: NSRange, quote: String) -> Bool {
            guard let chapter = chapters[chapterID], range.location >= 0, range.length > 0,
                  range.location <= chapter.readingLength,
                  range.length <= chapter.readingLength - range.location else { return false }
            let text = chapter.readingText as NSString
            return text.rangeOfComposedCharacterSequences(for: range) == range && text.substring(with: range) == quote
        }
        guard annotations.allSatisfy({ valid(chapterID: $0.chapterID, range: $0.range, quote: $0.quote) }),
              drafts.allSatisfy({ valid(chapterID: $0.chapterID, range: $0.range, quote: $0.quote) }) else {
            throw CocoaError(.coderReadCorrupt)
        }
    }
}
