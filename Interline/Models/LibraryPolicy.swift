import Foundation

public enum ShelfSort: String, CaseIterable, Identifiable {
    case recentlyRead = "最近阅读", title = "书名", imported = "最近导入"
    public var id: String { rawValue }
}
public enum ShelfFilter: String, CaseIterable, Identifiable {
    case all = "全部", unread = "未读", reading = "在读", finished = "已读"
    public var id: String { rawValue }
}
public enum LibraryPolicy {
    public static func filtered(_ books: [Book], query: String, filter: ShelfFilter, sort: ShelfSort) -> [Book] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return books.filter { book in
            let matches = query.isEmpty || book.title.localizedCaseInsensitiveContains(query) || book.author.localizedCaseInsensitiveContains(query)
            let status: Bool
            switch filter {
            case .all: status = true
            case .unread: status = book.readingLocation == nil && book.progressPercentage == 0
            case .reading: status = (book.readingLocation != nil || book.progressPercentage > 0) && book.progressPercentage < 100
            case .finished: status = book.progressPercentage >= 100
            }
            return matches && status
        }.sorted { left, right in
            switch sort {
            case .recentlyRead: return left.lastReadDate == right.lastReadDate ? left.id < right.id : left.lastReadDate > right.lastReadDate
            case .title:
                let order = left.title.localizedStandardCompare(right.title)
                return order == .orderedSame ? left.id < right.id : order == .orderedAscending
            case .imported: return (left.importedAt ?? .distantPast) == (right.importedAt ?? .distantPast) ? left.id < right.id : (left.importedAt ?? .distantPast) > (right.importedAt ?? .distantPast)
            }
        }
    }
}

public struct ReadingHighlight: Sendable {
    public let bookID: String
    public let chapterID: String
    public let range: NSRange
}
