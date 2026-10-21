import CoreText
import UIKit
import SwiftUI

/// Render-only objects remain on the main actor. Background work returns plain ranges.
@MainActor
public final class ChapterPagination {
    public let text: NSAttributedString
    public let pages: [PageSlice]
    public let size: CGSize
    private let framesetter: CTFramesetter

    init(text: NSAttributedString, pages: [PageSlice], size: CGSize) {
        self.text = text
        self.pages = pages
        self.size = size
        framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
    }

    public func frame(at index: Int) -> CTFrame {
        let range = pages[index].range
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        return CTFramesetterCreateFrame(framesetter, CFRange(location: range.location, length: range.length), path, nil)
    }

    public var frames: [CTFrame] { pages.indices.map { frame(at: $0) } }

    public func pageIndex(containing offset: Int) -> Int {
        pages.firstIndex(where: { $0.contains(max(0, offset)) }) ?? max(0, pages.count - 1)
    }
}

public enum PaginationError: Error {
    case viewportTooSmall
}

public enum ReaderPaginator {
    @MainActor public static func paginate(chapter: Chapter, size: CGSize, preferences: ReadingPreferences) throws -> ChapterPagination {
        let pages = try pageRanges(chapter: chapter, size: size, preferences: preferences)
        return ChapterPagination(text: attributedText(chapter: chapter, preferences: preferences), pages: pages, size: size)
    }

    public static func attributedText(chapter: Chapter, preferences: ReadingPreferences) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = preferences.lineSpacing
        paragraph.paragraphSpacing = preferences.fontSize * (preferences.paragraphSpacing ?? 0.5)
        paragraph.firstLineHeadIndent = preferences.fontSize * 2
        paragraph.lineBreakMode = .byWordWrapping
        let text = NSMutableAttributedString(string: chapter.readingText, attributes: [
            .font: font(size: preferences.fontSize, family: preferences.fontFamily),
            .foregroundColor: UIColor(preferences.theme.textColor),
            .paragraphStyle: paragraph
        ])
        if !chapter.title.isEmpty {
            let heading = NSMutableParagraphStyle()
            heading.lineSpacing = preferences.lineSpacing
            heading.paragraphSpacing = preferences.fontSize
            text.addAttributes([
                .font: font(size: preferences.fontSize + 4, family: preferences.fontFamily),
                .paragraphStyle: heading
            ], range: NSRange(location: 0, length: chapter.title.utf16.count))
        }
        return text
    }

    public static func pageRanges(chapter: Chapter, size: CGSize, preferences: ReadingPreferences) throws -> [PageSlice] {
        guard size.width >= 44, size.height >= preferences.fontSize * 2 else { throw PaginationError.viewportTooSmall }
        let text = attributedText(chapter: chapter, preferences: preferences)
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var pages: [PageSlice] = []
        var offset = 0
        // Return exact ranges from a whole-chapter layout. The renderer builds its
        // own frame from the same full text/styles, never a reflowed substring.
        repeat {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard text.length == 0 || visible.length > 0 else { throw PaginationError.viewportTooSmall }
            pages.append(PageSlice(chapterID: chapter.id, pageIndex: pages.count,
                                   range: NSRange(location: offset, length: visible.length)))
            offset += visible.length
        } while offset < text.length
        return pages
    }

    private static func font(size: CGFloat, family: ReadingFontFamily) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard family == .serif, let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
