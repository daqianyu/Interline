import Foundation

public struct PageSlice: Identifiable, Sendable, Hashable {
    public let chapterID: String
    public let pageIndex: Int
    public let range: NSRange

    public var id: String { "\(chapterID):\(range.location):\(range.length)" }
    public var endOffset: Int { NSMaxRange(range) }

    public func contains(_ offset: Int) -> Bool {
        offset >= range.location && offset < endOffset
    }
}

/// The displayed text and its chapter offset are captured together before a sheet opens.
/// Reader reflow cannot change what a selection refers to.
public struct ReadingSelectionSnapshot: Identifiable, Sendable {
    public let id = UUID()
    public let bookID: String
    public let page: PageSlice
    public let text: String
    public let preferences: ReadingPreferences
}
