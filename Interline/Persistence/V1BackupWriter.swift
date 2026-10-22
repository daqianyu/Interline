import Foundation

/// Retains one output Data and at most one hydrated book, rather than the whole library.
/// The later file-container format will remove the full-output buffer as well.
enum V1BackupWriter {
    static func encode(books: [Book], removedBooks: [Book], preferences: ReadingPreferences,
                       bookmarks: [Bookmark], annotations: [ReadingAnnotation], drafts: [NoteDraft],
                       createdAt: Date = Date(), maximumBytes: Int = ReadingStorage.maximumBackupBytes,
                       contentsURL: (String) -> URL) throws -> Data {
        try Task.checkCancellation()
        guard maximumBytes >= 0, maximumBytes <= ReadingStorage.maximumBackupBytes else {
            throw LibraryBackupError.tooLarge
        }
        let all = books + removedBooks
        let ids = try BackupValidation.bookIDs(all)
        let marks = bookmarks.filter { ids.contains($0.bookId) }
        let notes = annotations.filter { ids.contains($0.bookID) }
        let savedDrafts = drafts.filter { ids.contains($0.bookID) }
        try BackupValidation.references(bookIDs: ids, bookmarks: marks, annotations: notes, drafts: savedDrafts)

        // Complete this pass before reading any body. Source bytes are a resource
        // budget, not a prediction of final JSON size (which is checked separately).
        var sourceRemaining = maximumBytes
        func consume(_ count: Int) throws {
            guard count <= sourceRemaining else { throw LibraryBackupError.tooLarge }
            sourceRemaining -= count
        }
        for book in all {
            try Task.checkCancellation()
            try consume(book.id.utf8.count)
            try consume(book.title.utf8.count)
            try consume(book.author.utf8.count)
            if book.chapters.isEmpty {
                try consume(BoundedBackupInput.fileSize(contentsURL(book.id)))
            } else {
                for chapter in book.chapters {
                    try consume(chapter.id.utf8.count)
                    try consume(chapter.title.utf8.count)
                    for paragraph in chapter.content { try consume(paragraph.utf8.count) }
                }
            }
        }
        for note in notes { try consume(note.quote.utf8.count); try consume(note.note.utf8.count) }
        for draft in savedDrafts { try consume(draft.quote.utf8.count); try consume(draft.text.utf8.count) }

        let notesByBook = Dictionary(grouping: notes, by: \.bookID)
        let draftsByBook = Dictionary(grouping: savedDrafts, by: \.bookID)
        var output = BoundedJSON(maximumBytes: maximumBytes)
        func appendBooks(_ values: [Book]) throws {
            try output.literal("[")
            for (index, saved) in values.enumerated() {
                try Task.checkCancellation()
                if index > 0 { try output.literal(",") }
                try autoreleasepool {
                    var book = saved
                    if book.chapters.isEmpty {
                        let data = try BoundedBackupInput.read(contentsURL(book.id), maximumBytes: maximumBytes)
                        book.chapters = try JSONDecoder().decode([Chapter].self, from: data)
                    }
                    try BackupValidation.book(book, annotations: notesByBook[book.id] ?? [], drafts: draftsByBook[book.id] ?? [])
                    book.contentsUnavailable = false
                    try output.value(book)
                }
            }
            try output.literal("]")
        }
        try output.literal("{\"version\":1,\"createdAt\":")
        try output.value(createdAt)
        try output.literal(",\"books\":")
        try appendBooks(books)
        try output.literal(",\"removedBooks\":")
        try appendBooks(removedBooks)
        try output.literal(",\"preferences\":")
        try output.value(preferences)
        try output.literal(",\"bookmarks\":")
        try output.array(marks)
        try output.literal(",\"annotations\":")
        try output.array(notes)
        try output.literal(",\"drafts\":")
        try output.array(savedDrafts)
        try output.literal("}")
        try Task.checkCancellation()
        return output.data
    }

    private struct BoundedJSON {
        let maximumBytes: Int
        private(set) var data = Data()

        mutating func append(_ bytes: Data) throws {
            try Task.checkCancellation()
            guard bytes.count <= maximumBytes - data.count else { throw LibraryBackupError.tooLarge }
            data.append(bytes)
        }
        mutating func literal(_ value: String) throws { try append(Data(value.utf8)) }
        mutating func value<T: Encodable>(_ value: T) throws { try append(JSONEncoder().encode(value)) }
        mutating func array<T: Encodable>(_ values: [T]) throws {
            try literal("[")
            for (index, item) in values.enumerated() {
                if index > 0 { try literal(",") }
                try autoreleasepool { try value(item) }
            }
            try literal("]")
        }
    }
}
