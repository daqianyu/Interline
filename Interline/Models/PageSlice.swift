import Foundation

// MARK: - Page Slice for Paginated Reader
public struct PageSlice: Identifiable, Sendable, Hashable {
    public let id: String
    public let chapterIndex: Int
    public let pageIndex: Int
    public let totalPagesInChapter: Int
    public let chapterTitle: String
    public let paragraphs: [String]
    public let isChapterFirstPage: Bool

    public init(
        id: String = UUID().uuidString,
        chapterIndex: Int,
        pageIndex: Int,
        totalPagesInChapter: Int,
        chapterTitle: String,
        paragraphs: [String],
        isChapterFirstPage: Bool
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.pageIndex = pageIndex
        self.totalPagesInChapter = totalPagesInChapter
        self.chapterTitle = chapterTitle
        self.paragraphs = paragraphs
        self.isChapterFirstPage = isChapterFirstPage
    }
}
