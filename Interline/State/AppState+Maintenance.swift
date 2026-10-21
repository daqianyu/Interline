import Foundation

extension AppState {
    @discardableResult public func restoreRemovedBook(id: String) -> Bool {
        guard !isMaintenanceBusy, !isImporting, let book = maintenance.removedBooks.first(where: { $0.id == id }) else { return false }
        var next = maintenance
        next.removedBooks.removeAll { $0.id == id }
        var restored = book
        restored.contentsUnavailable = false
        var library = books
        if !library.contains(where: { $0.id == id }) { library.insert(restored, at: min(deletedBookBackup?.book.id == id ? (deletedBookBackup?.index ?? library.count) : library.count, library.count)) }
        do {
            try storage.beginTransaction()
            guard storage.saveMaintenance(next), storage.saveBooks(library) else { throw CocoaError(.fileWriteUnknown) }
            try storage.commitTransaction()
        } catch { _ = storage.recoverInterruptedRestore(); showFailure("撤销移出失败，请重试：" + (storage.lastError ?? "保存失败"), action: deletedBookBackup?.book.id == id ? .undoRemoval : nil); return false }
        maintenance = next
        books = storage.loadBooks(includeContents: !loadsContentsOnDemand)
        showToast("已恢复《\(book.title)》")
        return true
    }

    public func retryPendingDeletions() {
        guard !isMaintenanceBusy, !isImporting else { return }
        var next = maintenance
        for task in maintenance.pendingDeletions {
            let notes = annotations.filter { $0.bookID != task.id }
            let marks = bookmarks.filter { $0.bookId != task.id }
            let remainingDrafts = drafts.filter { $0.bookID != task.id }
            guard storage.saveAnnotations(notes), storage.saveBookmarks(marks), storage.saveDrafts(remainingDrafts) else { continue }
            annotations = notes; bookmarks = marks; drafts = remainingDrafts
            guard storage.purgeContents(bookID: task.id) else { continue }
            next.pendingDeletions.removeAll { $0.id == task.id }
        }
        guard storage.saveMaintenance(next) else { showFailure(storage.lastError ?? "清理状态保存失败", action: .retryCleanup); return }
        maintenance = next
        if next.pendingDeletions.isEmpty { showToast("数据清理已完成") }
        else { showFailure("部分数据尚未清理，可在数据与存储中重试", action: .retryCleanup) }
    }

    public func recoveryFiles() -> [RecoveryFile] { storage.recoveryFiles() }
    public func retryInterruptedRestore() {
        guard storage.recoverInterruptedRestore() else { showFailure(storage.lastError ?? "恢复失败"); return }
        reloadLibrary()
        showToast("数据恢复检查已完成")
    }
    private func reloadLibrary() {
        books = storage.loadBooks(includeContents: !loadsContentsOnDemand)
        maintenance = storage.loadMaintenance(); drafts = storage.loadDrafts()
        bookmarks = storage.loadBookmarks(); annotations = storage.loadAnnotations(); preferences = storage.loadPreferences()
    }

    public func exportLibraryBackup() async throws -> Data {
        guard !isMaintenanceBusy, !isImporting else { throw CocoaError(.fileWriteUnknown) }
        isMaintenanceBusy = true
        defer { isMaintenanceBusy = false }
        return try await storage.buildBackup(books: books, maintenance: maintenance, preferences: preferences,
            bookmarks: bookmarks, annotations: annotations, drafts: drafts)
    }

    @discardableResult public func restoreLibraryBackup(_ data: Data) async -> Bool {
        guard !isMaintenanceBusy, !isImporting else { return false }
        closeReader()
        isMaintenanceBusy = true
        defer { isMaintenanceBusy = false }
        do {
            var backup = try await Task.detached(priority: .userInitiated) { try ReadingStorage.decodeBackup(data) }.value
            func available(_ value: Book) -> Book { var book = value; book.contentsUnavailable = false; return book }
            backup.books = backup.books.map(available)
            backup.removedBooks = backup.removedBooks.map(available)
            let existing = books + maintenance.removedBooks
            let existingIDs = Set(existing.map(\.id))
            let incoming = (backup.books + backup.removedBooks).filter { !existingIDs.contains($0.id) }
            // Existing book IDs are immutable: keep current metadata and reading records.
            // Repair only an absent body; never replace a present body from a backup.
            let absent = (backup.books + backup.removedBooks).filter { existingIDs.contains($0.id) && !FileManager.default.fileExists(atPath: storage.contentsURL(bookID: $0.id).path) }
            var nextMaintenance = maintenance
            nextMaintenance.removedBooks += backup.removedBooks.filter { !existingIDs.contains($0.id) }.map(\.metadata)
            let repairedIDs = Set(absent.map(\.id))
            let restoredIDs = Set((backup.books + backup.removedBooks).map(\.id))
            let nextBooks = books.map { value in
                var book = value
                if restoredIDs.contains(book.id) { book.contentsUnavailable = false }
                return book
            } + backup.books.filter { !existingIDs.contains($0.id) }
            nextMaintenance.removedBooks = nextMaintenance.removedBooks.map { value in
                var book = value
                if restoredIDs.contains(book.id) { book.contentsUnavailable = false }
                return book
            }
            let pendingIDs = Set(maintenance.pendingDeletions.map(\.id))
            guard incoming.allSatisfy({ !pendingIDs.contains($0.id) }) else { throw CocoaError(.fileWriteUnknown) }
            func merged<T>(_ current: [T], _ restored: [T], id: (T) -> String) -> [T] {
                let ids = Set(current.map(id)); return current + restored.filter { !ids.contains(id($0)) }
            }
            let notes = merged(annotations, backup.annotations, id: { $0.id })
            let marks = merged(bookmarks, backup.bookmarks, id: { $0.id })
            let savedDrafts = merged(drafts, backup.drafts, id: { $0.id })
            let store = storage
            let collisions = (backup.books + backup.removedBooks).filter { existingIDs.contains($0.id) && !repairedIDs.contains($0.id) }
            try await Task.detached(priority: .userInitiated) {
                for book in collisions {
                    guard try store.readContents(bookID: book.id) == book.chapters else { throw CocoaError(.fileReadCorruptFile) }
                }
            }.value
            try storage.beginTransaction()
            try await Task.detached(priority: .userInitiated) {
                for book in incoming + absent { try Task.checkCancellation(); try store.stageContents(of: book) }
            }.value
            guard storage.saveAnnotations(notes), storage.saveBookmarks(marks), storage.saveDrafts(savedDrafts), storage.saveMaintenance(nextMaintenance) else { throw CocoaError(.fileWriteUnknown) }
            if existing.isEmpty, !storage.savePreferences(backup.preferences) { throw CocoaError(.fileWriteUnknown) }
            for book in incoming where !storage.saveRecord(for: book) { throw CocoaError(.fileWriteUnknown) }
            guard storage.saveBooks(nextBooks) else { throw CocoaError(.fileWriteUnknown) }
            try storage.commitTransaction()
            reloadLibrary()
            showToast("备份已合并，已有书籍的记录保持不变")
            return true
        } catch {
            _ = storage.recoverInterruptedRestore()
            showFailure("恢复未完成，原有资料已保留：\(error.localizedDescription)")
            return false
        }
    }

    func annotationChapter(bookID: String, chapterID: String) -> Chapter? {
        if let chapter = books.first(where: { $0.id == bookID })?.chapters.first(where: { $0.id == chapterID }) { return chapter }
        return (try? storage.readContents(bookID: bookID))?.first { $0.id == chapterID }
    }
    public func draft(for id: String) -> NoteDraft? { drafts.first { $0.id == id } }
    @discardableResult public func saveDraft(_ draft: NoteDraft) -> Bool {
        var next = drafts
        next.removeAll { $0.id == draft.id }
        if !draft.text.isEmpty { next.append(draft) }
        guard storage.saveDrafts(next) else { showFailure(storage.lastError ?? "草稿保存失败，请保留编辑页"); return false }
        drafts = next
        return true
    }
    @discardableResult public func removeDraft(id: String) -> Bool {
        let next = drafts.filter { $0.id != id }
        guard storage.saveDrafts(next) else { showFailure(storage.lastError ?? "草稿清理失败"); return false }
        drafts = next
        return true
    }

    public func details(for book: Book) async throws -> Book {
        if !book.chapters.isEmpty { return book }
        let store = storage
        do {
            let chapters = try await contentsLoader.load(bookID: book.id, storage: store)
            var loaded = book; loaded.chapters = chapters; loaded.updateChapterSummaries()
            return loaded
        } catch is CancellationError { throw CancellationError() }
        catch {
            if let index = books.firstIndex(where: { $0.id == book.id }) { books[index].contentsUnavailable = true }
            throw error
        }
    }
}
