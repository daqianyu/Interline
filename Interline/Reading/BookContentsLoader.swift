import Foundation

/// Serializes book reads so rapid switching cannot start many full-body decodes
/// simultaneously. A cancelled queued request exits before reading its file.
actor BookContentsLoader {
    private let beforeRead: (@Sendable () async -> Void)?

    init(beforeRead: (@Sendable () async -> Void)? = nil) { self.beforeRead = beforeRead }

    func load(bookID: String, storage: ReadingStorage) async throws -> [Chapter] {
        if let beforeRead { await beforeRead() }
        try Task.checkCancellation()
        return try storage.readContents(bookID: bookID)
    }

    func validateChapter(for draft: NoteDraft, storage: ReadingStorage, cached: Chapter?) async throws {
        try Task.checkCancellation()
        let chapter: Chapter
        if let cached { chapter = cached }
        else {
            let chapters = try await load(bookID: draft.bookID, storage: storage)
            guard let target = chapters.first(where: { $0.id == draft.chapterID }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            chapter = target
        }
        try Self.validate(draft, chapter: chapter)
        try Task.checkCancellation()
    }

    nonisolated static func validate(_ draft: NoteDraft, chapter: Chapter) throws {
        let range = draft.range
        guard chapter.id == draft.chapterID, range.location >= 0, range.length > 0,
              range.location <= chapter.readingLength,
              range.length <= chapter.readingLength - range.location else { throw CocoaError(.fileReadCorruptFile) }
        let text = chapter.readingText
        let source = text as NSString
        guard Range(range, in: text) != nil,
              source.rangeOfComposedCharacterSequences(for: range) == range,
              source.substring(with: range) == draft.quote else { throw CocoaError(.fileReadCorruptFile) }
    }
}
