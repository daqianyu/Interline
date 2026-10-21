import Foundation

// MARK: - Chapter Model
public struct Chapter: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public var title: String { didSet { refreshCounts() } }
    public var content: [String] { didSet { refreshCounts() } }
    private var cachedReadingLength = 0
    private var cachedCharacterCount = 0

    public init(id: String, title: String, content: [String]) {
        self.id = id
        self.title = title
        self.content = content
        refreshCounts()
    }

    private enum CodingKeys: String, CodingKey { case id, title, content }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id),
                  title: try values.decode(String.self, forKey: .title),
                  content: try values.decode([String].self, forKey: .content))
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(content, forKey: .content)
    }

    // One canonical string for pagination, progress, search and annotation anchors.
    public var readingText: String {
        ([title] + content).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    public var readingLength: Int { cachedReadingLength }
    public var characterCount: Int { cachedCharacterCount }

    private mutating func refreshCounts() {
        let parts = ([title] + content).filter { !$0.isEmpty }
        cachedReadingLength = parts.reduce(0) { $0 + $1.utf16.count } + max(0, parts.count - 1) * 2
        cachedCharacterCount = content.reduce(0) { $0 + $1.count }
    }
}

public struct ChapterSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let readingLength: Int
    public let characterCount: Int
    public init(_ chapter: Chapter) {
        id = chapter.id; title = chapter.title
        readingLength = chapter.readingLength; characterCount = chapter.characterCount
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
    public var importedAt: Date?
    public var chapterSummaries: [ChapterSummary]?
    public var contentsUnavailable: Bool?

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
        self.importedAt = Date()
        self.chapterSummaries = chapters.map(ChapterSummary.init)
        self.contentsUnavailable = false
        self.contentFingerprint = nil
        self.sourceEncoding = nil
        self.readingLocation = nil
        self.visibleEndOffset = nil
    }

    public var totalCharacters: Int {
        summaries.reduce(0) { $0 + $1.characterCount }
    }

    public var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    public var summaries: [ChapterSummary] {
        chapters.isEmpty ? (chapterSummaries ?? []) : chapters.map(ChapterSummary.init)
    }
    public var currentChapterTitle: String? {
        let values = summaries
        return values.indices.contains(currentChapterIndex) ? values[currentChapterIndex].title : nil
    }
    public mutating func updateChapterSummaries() {
        if !chapters.isEmpty { chapterSummaries = chapters.map(ChapterSummary.init) }
    }
    public var metadata: Book {
        var value = self
        value.updateChapterSummaries()
        value.chapters = []
        return value
    }
    public var progressPercentage: Double {
        let values = summaries
        guard values.indices.contains(currentChapterIndex) else { return 0 }
        let total = values.reduce(0) { $0 + $1.readingLength }
        guard total > 0 else { return 0 }
        let previous = values.prefix(currentChapterIndex).reduce(0) { $0 + $1.readingLength }
        let current = min(values[currentChapterIndex].readingLength, max(0, visibleEndOffset ?? 0))
        return min(100, Double(previous + current) / Double(total) * 100)
    }
}
