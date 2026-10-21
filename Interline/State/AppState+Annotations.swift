import Foundation

extension AppState {
    public var currentBookAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.bookID == activeBookId }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult public func addAnnotation(bookID: String, chapterID: String, range: NSRange, note: String = "") -> Bool {
        guard let chapter = annotationChapter(bookID: bookID, chapterID: chapterID),
              range.location >= 0, range.length > 0, range.location <= chapter.readingLength,
              range.length <= chapter.readingLength - range.location,
              Range(range, in: chapter.readingText) != nil else { return false }
        let source = chapter.readingText as NSString
        guard source.rangeOfComposedCharacterSequences(for: range) == range else { return false }
        var next = annotations
        if let index = next.firstIndex(where: { $0.bookID == bookID && $0.chapterID == chapterID && $0.range == range }) {
            if !note.isEmpty { next[index].note = note }
        } else {
            next.append(ReadingAnnotation(bookID: bookID, chapterID: chapterID, range: range,
                quote: (chapter.readingText as NSString).substring(with: range), note: note))
        }
        guard storage.saveAnnotations(next) else { checkSave(false); return false }
        annotations = next
        showToast(note.isEmpty ? "已添加标注" : "笔记已保存")
        return true
    }

    @discardableResult public func updateAnnotation(id: String, note: String) -> Bool {
        var next = annotations
        guard let index = next.firstIndex(where: { $0.id == id }) else { showFailure("笔记已不存在，草稿仍会保留"); return false }
        next[index].note = note
        guard storage.saveAnnotations(next) else { checkSave(false); return false }
        annotations = next
        return true
    }

    public func removeAnnotation(id: String) {
        let next = annotations.filter { $0.id != id }
        if storage.saveAnnotations(next) { annotations = next } else { checkSave(false) }
    }

    public func removeBookmark(id: String) {
        let next = bookmarks.filter { $0.id != id }
        if storage.saveBookmarks(next) { bookmarks = next } else { checkSave(false) }
    }

    public func notesText(for bookID: String) -> String {
        let title = books.first(where: { $0.id == bookID })?.title ?? "阅读笔记"
        let notes = annotations.filter { $0.bookID == bookID }.sorted { $0.createdAt < $1.createdAt }
        return ([title] + notes.map { "摘录：\($0.quote)\n笔记：\($0.note)" }).joined(separator: "\n\n")
    }
}
