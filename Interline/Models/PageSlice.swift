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
