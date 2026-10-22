import Foundation

extension AppState {
    @discardableResult public func restoreRemovedBook(id: String) -> Bool {
        guard !isMaintenanceBusy, !isImporting, let book = maintenance.removedBooks.first(where: { $0.id == id }) else { return false }
        guard requireSettledDrafts() else { return false }
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

    @discardableResult public func retryPendingDeletions() -> LibraryActionResult {
        guard !isMaintenanceBusy, !isImporting else { return actionFailure("资料正在处理，请稍后重试清理") }
        guard requireSettledDrafts() else { return .failure("仍有未保存的草稿，请先保存或重试") }
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
        guard storage.saveMaintenance(next) else { return actionFailure(storage.lastError ?? "清理状态保存失败") }
        maintenance = next
        if next.pendingDeletions.isEmpty { showToast("数据清理已完成"); return .success }
        let message = "部分数据尚未清理，可在数据与存储中重试"
        showFailure(message, action: .retryCleanup)
        return .failure(message)
    }

    public func recoveryFiles() -> [RecoveryFile] { storage.recoveryFiles() }
    @discardableResult public func retryInterruptedRestore() -> LibraryActionResult {
        guard !isMaintenanceBusy, !isImporting, requireSettledDrafts() else { return actionFailure("资料正在处理或有未保存草稿，请稍后重试恢复") }
        guard storage.recoverInterruptedRestore() else { return actionFailure(storage.lastError ?? "恢复失败") }
        reloadLibrary()
        showToast("数据恢复检查已完成")
        return .success
    }
    private func reloadLibrary() {
        noteLibraryRevision = UUID()
        books = storage.loadBooks(includeContents: !loadsContentsOnDemand)
        maintenance = storage.loadMaintenance(); drafts = storage.loadDrafts()
        draftSaveStates = [:]
        bookmarks = storage.loadBookmarks(); annotations = storage.loadAnnotations(); preferences = storage.loadPreferences()
    }

    public func exportLibraryBackup() async throws -> Data {
        guard !isMaintenanceBusy, !isImporting else { throw CocoaError(.fileWriteUnknown) }
        isMaintenanceBusy = true
        defer { isMaintenanceBusy = false }
        guard await flushDrafts() else { throw CocoaError(.fileWriteUnknown) }
        return try await storage.buildBackup(books: books, maintenance: maintenance, preferences: preferences,
            bookmarks: bookmarks, annotations: annotations, drafts: drafts)
    }

    public func exportLibraryBackupFile() async throws -> BackupExport {
        guard !isMaintenanceBusy, !isImporting else { throw CocoaError(.fileWriteUnknown) }
        isMaintenanceBusy = true
        defer { isMaintenanceBusy = false }
        guard await flushDrafts() else { throw CocoaError(.fileWriteUnknown) }
        let active = books, removed = maintenance.removedBooks, settings = preferences
        let marks = bookmarks, notes = annotations, savedDrafts = drafts, store = storage
        return try await BackupWorker.run {
            try BackupContainer.export(books: active, removedBooks: removed, preferences: settings,
                bookmarks: marks, annotations: notes, drafts: savedDrafts,
                contentsURL: { store.contentsURL(bookID: $0) })
        }
    }

    @discardableResult public func restoreLibraryBackup(_ data: Data) async -> Bool {
        await restoreLibraryBackup(preparing: { try BackupContainer.prepareLegacy(data) })
    }

    @discardableResult public func restoreLibraryBackup(_ prepared: PreparedLibraryBackup) async -> Bool {
        await restoreLibraryBackup(preparing: { prepared })
    }

    private func restoreLibraryBackup(preparing: @escaping @Sendable () throws -> PreparedLibraryBackup) async -> Bool {
        guard !isMaintenanceBusy, !isImporting else { return false }
        isMaintenanceBusy = true
        defer { isMaintenanceBusy = false }
        guard await flushDrafts() else { showFailure("草稿尚未保存，恢复未开始，请先重试保存草稿"); return false }
        closeReader()
        do {
            let prepared = try await BackupWorker.run(preparing)
            var backup = prepared.metadata
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
            try await BackupWorker.run {
                for book in collisions {
                    try autoreleasepool {
                        guard try store.readContents(bookID: book.id) == prepared.readBook(book).chapters else { throw CocoaError(.fileReadCorruptFile) }
                    }
                }
            }
            try storage.beginTransaction()
            try await BackupWorker.run {
                for book in incoming + absent {
                    try Task.checkCancellation()
                    try autoreleasepool { try store.stageContents(of: prepared.readBook(book)) }
                }
            }
            try Task.checkCancellation()
            guard storage.saveAnnotations(notes), storage.saveBookmarks(marks), storage.saveDrafts(savedDrafts), storage.saveMaintenance(nextMaintenance) else { throw CocoaError(.fileWriteUnknown) }
            if existing.isEmpty, !storage.savePreferences(backup.preferences) { throw CocoaError(.fileWriteUnknown) }
            for book in incoming where !storage.saveRecord(for: book) { throw CocoaError(.fileWriteUnknown) }
            guard storage.saveBooks(nextBooks) else { throw CocoaError(.fileWriteUnknown) }
            try storage.commitTransaction()
            reloadLibrary()
            showToast("备份已合并，已有书籍的记录保持不变")
            return true
        } catch {
            if storage.recoverInterruptedRestore() {
                showFailure("恢复未完成，原有资料已保留：\(error.localizedDescription)")
            } else {
                showFailure("恢复未完成，且回滚尚未成功。恢复日志仍保留，相关写入已暂停；请在数据与存储中重试中断的数据恢复。")
            }
            return false
        }
    }

    func annotationChapter(bookID: String, chapterID: String) -> Chapter? {
        if let chapter = books.first(where: { $0.id == bookID })?.chapters.first(where: { $0.id == chapterID }) { return chapter }
        return (try? storage.readContents(bookID: bookID))?.first { $0.id == chapterID }
    }
    public func details(for book: Book) async throws -> Book {
        if !book.chapters.isEmpty { return book }
        let store = storage
        do {
            let chapters = try await contentsLoader.load(bookID: book.id, storage: store)
            try Task.checkCancellation()
            var loaded = book; loaded.chapters = chapters; loaded.updateChapterSummaries()
            return loaded
        } catch is CancellationError { throw CancellationError() }
        catch {
            if let index = books.firstIndex(where: { $0.id == book.id }) { books[index].contentsUnavailable = true }
            throw error
        }
    }
}
