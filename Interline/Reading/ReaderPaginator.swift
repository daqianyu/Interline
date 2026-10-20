import CoreText
import UIKit
import SwiftUI

/// The current chapter's layout is reused across page turns and replaced on resize.
@MainActor
public final class ChapterPagination {
    public let text: NSAttributedString
    public let pages: [PageSlice]
    public let frames: [CTFrame]
    public let size: CGSize

    init(text: NSAttributedString, pages: [PageSlice], frames: [CTFrame], size: CGSize) {
        self.text = text
        self.pages = pages
        self.frames = frames
        self.size = size
    }

    public func pageIndex(containing offset: Int) -> Int {
        pages.firstIndex(where: { $0.contains(max(0, offset)) }) ?? max(0, pages.count - 1)
    }
}

public enum PaginationError: Error {
    case viewportTooSmall
}

@MainActor
public enum ReaderPaginator {
    public static func paginate(chapter: Chapter, size: CGSize, preferences: ReadingPreferences) throws -> ChapterPagination {
        guard size.width >= 44, size.height >= preferences.fontSize * 2 else {
            throw PaginationError.viewportTooSmall
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = preferences.lineSpacing
        paragraph.paragraphSpacing = preferences.fontSize * 0.5
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
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var pages: [PageSlice] = []
        var frames: [CTFrame] = []
        var offset = 0
        // Measure and draw the very same CTFrame; never reflow a page substring.
        repeat {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard text.length == 0 || visible.length > 0 else { throw PaginationError.viewportTooSmall }
            pages.append(PageSlice(chapterID: chapter.id, pageIndex: pages.count,
                                   range: NSRange(location: offset, length: visible.length)))
            frames.append(frame)
            offset += visible.length
        } while offset < text.length
        return ChapterPagination(text: text, pages: pages, frames: frames, size: size)
    }

    private static func font(size: CGFloat, family: ReadingFontFamily) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard family == .serif, let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}
