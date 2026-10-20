import Foundation

public struct BookSearchMatch: Identifiable, Sendable {
    public let chapterID: String
    public let chapterTitle: String
    public let range: NSRange
    public let snippet: String
    public var id: String { "\(chapterID):\(range.location)" }
    public var location: ReadingLocation { ReadingLocation(chapterID: chapterID, utf16Offset: range.location) }
}

public enum BookSearchService {
    public static let resultLimit = 200

    public static func search(book: Book, query: String) throws -> [BookSearchMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [BookSearchMatch] = []
        for chapter in book.chapters {
            try Task.checkCancellation()
            let text = chapter.readingText as NSString
            var start = 0
            while start < text.length && results.count < resultLimit {
                try Task.checkCancellation()
                let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                                       range: NSRange(location: start, length: text.length - start))
                guard found.location != NSNotFound && found.length > 0 else { break }
                let previewStart = max(0, found.location - 24)
                let preview = text.rangeOfComposedCharacterSequences(for:
                    NSRange(location: previewStart, length: min(text.length - previewStart, found.length + 72)))
                results.append(BookSearchMatch(chapterID: chapter.id, chapterTitle: chapter.title,
                    range: found, snippet: text.substring(with: preview).replacingOccurrences(of: "\n", with: " ")))
                start = NSMaxRange(found)
            }
            if results.count == resultLimit { break }
        }
        return results
    }
}
