import Foundation

extension AppState {
    public func importBook(_ imported: Book) async -> Bool {
        guard !isMaintenanceBusy, !isImporting else { return false }
        guard !maintenance.pendingDeletions.contains(where: { $0.id == imported.id }) else { showFailure("请先在数据与存储中完成此书的数据清理"); return false }
        let wasRemoved = maintenance.removedBooks.contains(where: { $0.id == imported.id })
        guard !imported.chapters.isEmpty else { showToast("没有可导入的正文"); return false }
        guard !books.contains(where: { $0.id == imported.id && $0.contentsUnavailable != true }) else { showToast("这本书已经在书架中"); return false }
        let repairing = wasRemoved || books.contains(where: { $0.id == imported.id })
        isImporting = true
        defer { isImporting = false }
        do {
            let store = storage
            try await Task.detached(priority: .userInitiated) { try store.stageContents(of: imported, replacing: repairing) }.value
            guard !books.contains(where: { $0.id == imported.id && $0.contentsUnavailable != true }) else { return false }
            if wasRemoved {
                isImporting = false
                return restoreRemovedBook(id: imported.id)
            }
            var book = imported
            if let record = storage.loadRecord(bookID: book.id), let anchor = record.location,
               let index = book.chapters.firstIndex(where: { $0.id == anchor.chapterID }) {
                book.currentChapterIndex = index
                book.currentPageIndex = record.pageIndex
                book.readingLocation = anchor
                book.visibleEndOffset = record.visibleEndOffset
            }
            var next = books
            if let index = next.firstIndex(where: { $0.id == book.id }) { next[index] = book }
            else { next.append(book) }
            guard storage.saveBooks(next) else { checkSave(false); return false }
            books = loadsContentsOnDemand ? next.map { $0.id == activeBookId && isReaderPresented ? $0 : $0.metadata } : next
            showToast("已导入《\(book.title)》")
            return true
        } catch { showFailure("正文保存失败：\(error.localizedDescription)"); return false }
    }

    public func updateBookMetadata(id: String, title: String, author: String) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var next = books
        next[index].title = title
        next[index].author = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知作者" : author
        if storage.saveBooks(next) { books = next; showToast("书籍信息已保存") }
        else { checkSave(false) }
    }

    public func permanentlyDeleteBook(id: String) {
        guard !isMaintenanceBusy, !isImporting else { return }
        guard let book = books.first(where: { $0.id == id }) ?? maintenance.removedBooks.first(where: { $0.id == id }) else { return }
        var next = maintenance
        next.removedBooks.removeAll { $0.id == id }
        if !next.pendingDeletions.contains(where: { $0.id == id }) { next.pendingDeletions.append(PendingDeletion(id: id, title: book.title, createdAt: Date())) }
        let active = books.filter { $0.id != id }
        do {
            try storage.beginTransaction()
            guard storage.saveMaintenance(next), storage.saveBooks(active) else { throw CocoaError(.fileWriteUnknown) }
            try storage.commitTransaction()
        } catch { _ = storage.recoverInterruptedRestore(); showFailure(storage.lastError ?? "删除失败，请重试"); return }
        maintenance = next; books = active; deletedBookBackup = nil
        if activeBookId == id { closeReader(); activeBookId = nil }
        pageCache.remove { $0.bookID == id }
        retryPendingDeletions()
    }

    public func jumpToLocation(bookID: String, location: ReadingLocation, highlight: NSRange? = nil, remember: Bool = true) {
        guard let target = books.first(where: { $0.id == bookID }),
              target.summaries.contains(where: { $0.id == location.chapterID }) || !isReaderPresented else { return }
        let previous = activeBook?.readingLocation
        let match = highlight.map { ReadingHighlight(bookID: bookID, chapterID: location.chapterID, range: $0) }
        if !isReaderPresented || activeBookId != bookID {
            pendingLocation = location; pendingHighlight = match
            openBook(target)
            return
        }
        guard var book = activeBook, let index = book.chapters.firstIndex(where: { $0.id == location.chapterID }) else { return }
        if remember, let previous, previous != location { navigationHistory.append(previous); if navigationHistory.count > 20 { navigationHistory.removeFirst() } }
        book.currentChapterIndex = index; book.currentPageIndex = 0; book.readingLocation = location; book.visibleEndOffset = nil
        activeBook = book
        isTOCPresented = false; isBookSearchPresented = false; areControlsVisible = false
        if let match { setSearchHighlight(match) } else { clearSearchHighlight() }
        rebuildPagination()
    }

    func rememberCurrentLocation() {
        if let location = activeBook?.readingLocation {
            navigationHistory.append(location)
            if navigationHistory.count > 20 { navigationHistory.removeFirst() }
        }
    }
    public func persistSession() {
        guard !isLoadingBook, !isMaintenanceBusy, let book = activeBook, !book.chapters.isEmpty else { return }
        checkSave(storage.saveRecord(for: book))
    }
    public func returnToPreviousLocation() {
        guard let id = activeBookId, let location = navigationHistory.popLast() else { return }
        jumpToLocation(bookID: id, location: location, remember: false)
    }
    func setSearchHighlight(_ highlight: ReadingHighlight) {
        highlightTask?.cancel(); searchHighlight = highlight
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.searchHighlight = nil
        }
    }
    func clearSearchHighlight() { highlightTask?.cancel(); searchHighlight = nil }

}
