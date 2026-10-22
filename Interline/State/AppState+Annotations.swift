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

    /// A retained draft may outlive its original annotation. Save it as a new
    /// annotation in that case, but never redirect it to a different quotation.
    @discardableResult public func saveDraftNote(_ draft: NoteDraft, text: String) -> Bool {
        guard canCommitDraft(draft), requireSettledDrafts() else { return false }
        guard let chapter = annotationChapter(bookID: draft.bookID, chapterID: draft.chapterID),
              (try? BookContentsLoader.validate(draft, chapter: chapter)) != nil else {
            showFailure("草稿对应的原文无法验证，输入已保留")
            return false
        }
        return commitDraftNote(draft, text: text)
    }

    /// The target belongs to the draft, never to the currently open reader.
    /// Loading/decoding and quotation validation run on the contents actor.
    @discardableResult public func saveDraftNoteAsync(_ draft: NoteDraft, text: String) async -> Bool {
        guard !Task.isCancelled, canCommitDraft(draft), requireSettledDrafts() else { return false }
        let revision = noteLibraryRevision
        let submittedDraft = self.draft(for: draft.id)
        let cached = books.first(where: { $0.id == draft.bookID })?.chapters.first { $0.id == draft.chapterID }
        do {
            try await contentsLoader.validateChapter(for: draft, storage: storage, cached: cached)
            try Task.checkCancellation()
            let currentDraft = self.draft(for: draft.id)
            guard revision == noteLibraryRevision, canCommitDraft(draft), requireSettledDrafts(),
                  submittedDraft?.updatedAt == currentDraft?.updatedAt,
                  submittedDraft?.text == currentDraft?.text else {
                showFailure("资料已变化或正在处理，输入已保留，请重试")
                return false
            }
            // No suspension between checking the current library and committing.
            return commitDraftNote(draft, text: text)
        } catch is CancellationError { return false }
        catch {
            showFailure("草稿对应的原文无法读取或摘录不匹配，输入已保留，请修复正文后重试")
            return false
        }
    }

    private func canCommitDraft(_ draft: NoteDraft) -> Bool {
        !isMaintenanceBusy && !isImporting &&
        !maintenance.pendingDeletions.contains(where: { $0.id == draft.bookID }) &&
        (books.contains(where: { $0.id == draft.bookID }) || maintenance.removedBooks.contains(where: { $0.id == draft.bookID }))
    }

    private func commitDraftNote(_ draft: NoteDraft, text: String) -> Bool {
        if let id = draft.annotationID, let existing = annotations.first(where: { $0.id == id }) {
            guard existing.bookID == draft.bookID, existing.chapterID == draft.chapterID,
                  existing.range == draft.range, existing.quote == draft.quote else {
                showFailure("草稿与原笔记不匹配，输入已保留")
                return false
            }
            return updateAnnotation(id: id, note: text)
        }
        var next = annotations
        if let index = next.firstIndex(where: { $0.bookID == draft.bookID && $0.chapterID == draft.chapterID && $0.range == draft.range }) {
            guard next[index].quote == draft.quote else { showFailure("草稿与原笔记不匹配，输入已保留"); return false }
            if !text.isEmpty { next[index].note = text }
        } else {
            next.append(ReadingAnnotation(bookID: draft.bookID, chapterID: draft.chapterID,
                range: draft.range, quote: draft.quote, note: text))
        }
        guard storage.saveAnnotations(next) else { checkSave(false); return false }
        annotations = next
        showToast("笔记已保存")
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
