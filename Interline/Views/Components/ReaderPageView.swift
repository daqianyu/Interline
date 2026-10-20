import CoreText
import SwiftUI
import UIKit

struct ReaderPageView: UIViewRepresentable {
    let pagination: ChapterPagination
    let pageIndex: Int

    func makeUIView(context: Context) -> ReaderDrawingView {
        let view = ReaderDrawingView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: ReaderDrawingView, context: Context) {
        view.pagination = pagination
        view.pageIndex = pageIndex
        view.setNeedsDisplay()
    }
}

final class ReaderDrawingView: UIView {
    var pagination: ChapterPagination?
    var pageIndex = 0

    override func draw(_ rect: CGRect) {
        guard let pagination, pagination.frames.indices.contains(pageIndex),
              let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: pagination.size.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(pagination.frames[pageIndex], context)
        context.restoreGState()
    }
}
