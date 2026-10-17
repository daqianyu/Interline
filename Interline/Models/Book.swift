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
    }

    public var totalCharacters: Int {
        chapters.reduce(0) { $0 + $1.characterCount }
    }

    public var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    public var progressPercentage: Double {
        guard !chapters.isEmpty else { return 0 }
        let totalChars = totalCharacters
        guard totalChars > 0 else {
            return Double(currentChapterIndex) / Double(chapters.count) * 100.0
        }
        var readChars = 0
        for i in 0..<min(currentChapterIndex, chapters.count) {
            readChars += chapters[i].characterCount
        }
        return min(100.0, max(0.0, (Double(readChars) / Double(totalChars)) * 100.0))
    }
}
