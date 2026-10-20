import Foundation

// MARK: - Chapter Model
public struct Chapter: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var title: String
    public var content: [String] // Paragraphs

    public init(id: String, title: String, content: [String]) {
        self.id = id
        self.title = title
        self.content = content
    }

    // One canonical string for pagination, progress, bookmarks and restoration.
    public var readingText: String {
        ([title] + content).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    public var readingLength: Int {
        let lengths = ([title] + content).filter { !$0.isEmpty }.map { $0.utf16.count }
        return lengths.reduce(0, +) + max(0, lengths.count - 1) * 2
    }

    public var characterCount: Int {
        content.reduce(0) { $0 + $1.count }
    }
}

// MARK: - Book Model
public struct Book: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var title: String
    public var author: String
    public var themeColorHex: String
    public var textColorHex: String
    public var currentChapterIndex: Int
    public var currentPageIndex: Int
    public var chapters: [Chapter]
    public var readingLocation: ReadingLocation?
    public var visibleEndOffset: Int?
    public var contentFingerprint: String?
    public var sourceEncoding: String?
    public var lastReadDate: Date

    public init(
        id: String,
        title: String,
        author: String,
        themeColorHex: String = "#1C1C1E",
        textColorHex: String = "#F2F2F7",
        currentChapterIndex: Int = 0,
        currentPageIndex: Int = 0,
        chapters: [Chapter],
        lastReadDate: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.themeColorHex = themeColorHex
        self.textColorHex = textColorHex
        self.currentChapterIndex = currentChapterIndex
        self.currentPageIndex = currentPageIndex
        self.chapters = chapters
        self.lastReadDate = lastReadDate
        self.contentFingerprint = nil
        self.sourceEncoding = nil
        self.readingLocation = nil
        self.visibleEndOffset = nil
    }

    public var totalCharacters: Int {
        chapters.reduce(0) { $0 + $1.characterCount }
    }

    public var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    public var progressPercentage: Double {
        guard chapters.indices.contains(currentChapterIndex) else { return 0 }
        let total = chapters.reduce(0) { $0 + $1.readingLength }
        guard total > 0 else { return 0 }
        let previous = chapters.prefix(currentChapterIndex).reduce(0) { $0 + $1.readingLength }
        let current = min(chapters[currentChapterIndex].readingLength, max(0, visibleEndOffset ?? 0))
        return min(100, Double(previous + current) / Double(total) * 100)
    }
}
