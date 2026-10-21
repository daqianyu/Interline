import CoreText
import SwiftUI
import UIKit

struct ReaderPageView: UIViewRepresentable {
    let pagination: ChapterPagination
    let pageIndex: Int
    let annotations: [ReadingAnnotation]
    let searchHighlight: ReadingHighlight?

    func makeUIView(context: Context) -> ReaderDrawingView {
        let view = ReaderDrawingView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }
    func updateUIView(_ view: ReaderDrawingView, context: Context) {
        view.pagination = pagination
        view.pageIndex = pageIndex
        view.annotations = annotations
        view.searchHighlight = searchHighlight
        view.setNeedsDisplay()
    }
}

final class ReaderDrawingView: UIView {
    var pagination: ChapterPagination?
    var pageIndex = 0
    var annotations: [ReadingAnnotation] = []
    var searchHighlight: ReadingHighlight?

    override func draw(_ rect: CGRect) {
        guard let pagination, pagination.pages.indices.contains(pageIndex),
              let context = UIGraphicsGetCurrentContext() else { return }
        let frame = pagination.frame(at: pageIndex)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: pagination.size.height)
        context.scaleBy(x: 1, y: -1)
        let notes = annotations.filter { $0.chapterID == pagination.pages[pageIndex].chapterID }
        let highlight = searchHighlight?.chapterID == pagination.pages[pageIndex].chapterID ? searchHighlight : nil
        let ranges = notes.map(\.range) + (highlight.map { [$0.range] } ?? [])
        if !ranges.isEmpty {
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = Array(repeating: CGPoint.zero, count: lines.count)
            if !origins.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins) }
            context.setFillColor(UIColor.systemYellow.withAlphaComponent(0.25).cgColor)
            for (index, line) in lines.enumerated() {
                let lineRange = CTLineGetStringRange(line)
                var ascent: CGFloat = 0, descent: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                for range in ranges {
                    let intersection = NSIntersectionRange(NSRange(location: lineRange.location, length: lineRange.length), range)
                    guard intersection.length > 0 else { continue }
                    let start = CTLineGetOffsetForStringIndex(line, intersection.location, nil)
                    let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(intersection), nil)
                    context.fill(CGRect(x: origins[index].x + min(start, end), y: origins[index].y - descent,
                                        width: abs(end - start), height: ascent + descent + 2))
                }
            }
        }
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
