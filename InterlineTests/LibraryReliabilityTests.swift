import XCTest
@testable import Interline

@MainActor
final class LibraryReliabilityTests: XCTestCase {
    @MainActor private struct Fixture {
        let storage: ReadingStorage
        let defaults: UserDefaults
        let name: String
        init() {
            name = "LibraryReliability-" + UUID().uuidString
            defaults = UserDefaults(suiteName: name)!
            storage = ReadingStorage(defaults: defaults, directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        }
        func clean() { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: storage.directory) }
    }
    private func book(_ suffix: String = "a") throws -> Book {
        try TXTImportService.parse(data: Data(("第一章 开始\n" + String(repeating: "长篇阅读与笔记测试。", count: 300) + suffix + "\n第二章 继续\n结尾正文").utf8), fileName: suffix + ".txt").book
    }

    func testRemovedBooksCanBeRecoveredAfterRelaunch() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        state.openBook(value); state.prepareReader(size: CGSize(width: 280, height: 400)); state.nextPage()
        let anchor = state.activeBook?.readingLocation
        state.deleteBook(id: value.id)
        let relaunched = AppState(storage: f.storage, usesBackgroundLayout: false)
        XCTAssertTrue(relaunched.books.isEmpty)
        XCTAssertEqual(relaunched.maintenance.removedBooks.map(\.id), [value.id])
        XCTAssertTrue(relaunched.restoreRemovedBook(id: value.id))
        XCTAssertEqual(relaunched.books.first?.readingLocation, anchor)
        XCTAssertTrue(relaunched.maintenance.removedBooks.isEmpty)
    }

    func testFullBackupRestoresReadingNotesDraftsSettingsAndRemovedBooks() async throws {
        let source = Fixture(), target = Fixture(); defer { source.clean(); target.clean() }
        let first = try book("first"), second = try book("removed")
        XCTAssertTrue(source.storage.saveBooks([first, second]))
        let state = AppState(storage: source.storage, usesBackgroundLayout: false)
        state.openBook(first); state.prepareReader(size: CGSize(width: 280, height: 400)); state.nextPage()
        let anchor = state.activeBook?.readingLocation
        state.updatePreferences { $0.fontSize = 22 }
        XCTAssertTrue(state.addAnnotation(bookID: first.id, chapterID: first.chapters[0].id, range: NSRange(location: 0, length: 3), note: "完整备份笔记"))
        state.toggleBookmark()
        let draft = NoteDraft(bookID: first.id, chapterID: first.chapters[0].id, range: NSRange(location: 0, length: 3), quote: "第一章", text: "尚未完成的草稿")
        XCTAssertTrue(state.saveDraft(draft))
        state.deleteBook(id: second.id)
        let data = try await state.exportLibraryBackup()
        XCTAssertTrue(target.storage.saveBooks([]))
        let restored = AppState(storage: target.storage, usesBackgroundLayout: false)
        let success = await restored.restoreLibraryBackup(data)
        XCTAssertTrue(success)
        XCTAssertEqual(restored.books.map(\.id), [first.id])
        XCTAssertEqual(restored.books.first?.readingLocation, anchor)
        XCTAssertEqual(restored.annotations.first?.note, "完整备份笔记")
        XCTAssertEqual(restored.bookmarks.count, 1)
        XCTAssertEqual(restored.drafts.first?.text, draft.text)
        XCTAssertEqual(restored.preferences.fontSize, 22)
        XCTAssertEqual(restored.maintenance.removedBooks.map(\.id), [second.id])
        XCTAssertTrue(restored.restoreRemovedBook(id: second.id))
        XCTAssertEqual(restored.books.count, 2)
    }

    func testBackupMergeKeepsCurrentMetadataAndNotesAndIsIdempotent() async throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage)
        XCTAssertTrue(state.addAnnotation(bookID: value.id, chapterID: value.chapters[0].id, range: NSRange(location: 0, length: 3), note: "旧笔记"))
        let data = try await state.exportLibraryBackup()
        let id = try XCTUnwrap(state.annotations.first?.id)
        XCTAssertTrue(state.updateAnnotation(id: id, note: "更新的笔记"))
        state.updateBookMetadata(id: value.id, title: "当前书名", author: "当前作者")
        let first = await state.restoreLibraryBackup(data), second = await state.restoreLibraryBackup(data)
        XCTAssertTrue(first && second)
        XCTAssertEqual(state.books.count, 1)
        XCTAssertEqual(state.books.first?.title, "当前书名")
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations.first?.note, "更新的笔记")
    }

    func testInvalidBackupDoesNotMutateLibrary() async throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let original = try Data(contentsOf: f.storage.catalogURL)
        let state = AppState(storage: f.storage)
        let result = await state.restoreLibraryBackup(Data("{\"version\":99}".utf8))
        XCTAssertFalse(result)
        XCTAssertEqual(try Data(contentsOf: f.storage.catalogURL), original)
        XCTAssertEqual(state.books.map(\.id), [value.id])
    }

    func testBackupRejectsDuplicateIDsAndMismatchedAnnotationQuotes() async throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage)
        var backup = try ReadingStorage.decodeBackup(try await state.exportLibraryBackup())
        backup.books.append(value)
        XCTAssertThrowsError(try ReadingStorage.decodeBackup(JSONEncoder().encode(backup)))
        backup.books = [value]
        backup.annotations = [ReadingAnnotation(bookID: value.id, chapterID: value.chapters[0].id, range: NSRange(location: 0, length: 3), quote: "不匹配")]
        XCTAssertThrowsError(try ReadingStorage.decodeBackup(JSONEncoder().encode(backup)))
    }

    func testInterruptedTransactionRestoresFilesAndReadingRecordsOnRelaunch() throws {
        let f = Fixture(); defer { f.clean() }
        let original = try book("original"), other = try book("other")
        XCTAssertTrue(f.storage.saveBooks([original])); XCTAssertTrue(f.storage.saveAnnotations([]))
        try f.storage.beginTransaction()
        XCTAssertTrue(f.storage.saveBooks([other])); XCTAssertTrue(f.storage.saveRecord(for: other))
        XCTAssertTrue(f.storage.saveDrafts([NoteDraft(bookID: other.id, chapterID: other.chapters[0].id, range: NSRange(location: 0, length: 3), quote: "第一章", text: "未提交")]))
        let relaunchedStorage = ReadingStorage(defaults: f.defaults, directory: f.storage.directory)
        let relaunched = AppState(storage: relaunchedStorage)
        XCTAssertEqual(relaunched.books.map(\.id), [original.id])
        XCTAssertTrue(relaunched.drafts.isEmpty)
        XCTAssertNil(relaunchedStorage.loadRecord(bookID: other.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.storage.directory.appendingPathComponent("restore-journal-v1.json").path))
    }

    func testCleanupQueueSurvivesFailureAndRetryDoesNotNeedReimport() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value])); XCTAssertTrue(f.storage.saveBooks([]))
        var pending = LibraryMaintenanceState()
        pending.pendingDeletions = [PendingDeletion(id: value.id, title: value.title, createdAt: Date())]
        XCTAssertTrue(f.storage.saveMaintenance(pending))
        let notesURL = f.storage.directory.appendingPathComponent("annotations-v1.json")
        try FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: false)
        let state = AppState(storage: f.storage)
        state.retryPendingDeletions()
        XCTAssertEqual(state.maintenance.pendingDeletions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.storage.contentsURL(bookID: value.id).path))
        try FileManager.default.removeItem(at: notesURL)
        state.retryPendingDeletions()
        XCTAssertTrue(state.maintenance.pendingDeletions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.storage.contentsURL(bookID: value.id).path))
    }

    func testNoteSaveFailureKeepsExistingAnnotationAndPersistentDraft() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage)
        XCTAssertTrue(state.addAnnotation(bookID: value.id, chapterID: value.chapters[0].id, range: NSRange(location: 0, length: 3), note: "原始笔记"))
        let annotation = try XCTUnwrap(state.annotations.first)
        let draft = NoteDraft(bookID: value.id, chapterID: annotation.chapterID, range: annotation.range, quote: annotation.quote, annotationID: annotation.id, text: "需要重试的输入")
        XCTAssertTrue(state.saveDraft(draft))
        let url = f.storage.directory.appendingPathComponent("annotations-v1.json")
        try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertFalse(state.updateAnnotation(id: annotation.id, note: draft.text))
        XCTAssertEqual(state.annotations.first?.note, "原始笔记")
        XCTAssertEqual(AppState(storage: f.storage).drafts.first?.text, draft.text)
        XCTAssertTrue(state.notice?.isError == true)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(state.updateAnnotation(id: annotation.id, note: draft.text))
        XCTAssertEqual(state.annotations.first?.note, draft.text)
    }

    func testLazyCatalogLoadsOnlyOpenedBookAndReleasesItOnClose() async throws {
        let f = Fixture(); defer { f.clean() }
        let first = try book("first"), second = try book("second")
        XCTAssertTrue(f.storage.saveBooks([first, second]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false, loadsContentsOnDemand: true)
        XCTAssertTrue(state.books.allSatisfy { $0.chapters.isEmpty })
        XCTAssertEqual(state.books[0].totalCharacters, first.totalCharacters)
        state.openBook(state.books[0]); await state.waitForBookLoad()
        XCTAssertFalse(state.activeBook?.chapters.isEmpty ?? true)
        state.prepareReader(size: CGSize(width: 280, height: 400)); state.nextPage()
        let anchor = state.activeBook?.readingLocation
        state.openBook(state.books[1]); await state.waitForBookLoad()
        XCTAssertTrue(state.books.first(where: { $0.id == first.id })?.chapters.isEmpty == true)
        state.handleMemoryWarning()
        XCTAssertEqual(state.activeBookId, second.id)
        state.closeReader()
        XCTAssertTrue(state.books.allSatisfy { $0.chapters.isEmpty })
        state.openBook(state.books[0]); await state.waitForBookLoad()
        XCTAssertEqual(state.activeBook?.readingLocation, anchor)
    }

    func testClosingDuringBookLoadDoesNotReopenReader() async throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage, loadsContentsOnDemand: true)
        state.openBook(state.books[0]); state.closeReader(); await state.waitForBookLoad()
        XCTAssertFalse(state.isReaderPresented)
        XCTAssertNil(state.pagination)
        XCTAssertTrue(state.books.allSatisfy { $0.chapters.isEmpty })
    }

    func testSearchHighlightAndReturnHistoryRestoreExactAnchor() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        state.openBook(value); state.prepareReader(size: CGSize(width: 280, height: 400)); state.nextPage()
        let anchor = try XCTUnwrap(state.activeBook?.readingLocation)
        let target = ReadingLocation(chapterID: value.chapters[1].id, utf16Offset: 2)
        state.jumpToLocation(bookID: value.id, location: target, highlight: NSRange(location: 2, length: 1))
        XCTAssertEqual(state.searchHighlight?.range, NSRange(location: 2, length: 1))
        XCTAssertEqual(state.navigationHistory.last, anchor)
        state.returnToPreviousLocation()
        XCTAssertEqual(state.activeBook?.readingLocation, anchor)
        XCTAssertTrue(state.navigationHistory.isEmpty)
    }

    func testAppearanceChangeKeepsPageRangesAndDoesNotStartReflow() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        state.openBook(value); state.prepareReader(size: CGSize(width: 280, height: 400)); state.nextPage()
        let pages = state.pagination?.pages, anchor = state.activeBook?.readingLocation
        state.updatePreferences { $0.theme = .night; $0.followsSystemAppearance = false }
        XCTAssertEqual(state.pagination?.pages, pages)
        XCTAssertEqual(state.activeBook?.readingLocation, anchor)
        XCTAssertFalse(state.isPaginating)
        state.updatePreferences { $0.paragraphSpacing = 1.5 }
        XCTAssertEqual(state.activeBook?.readingLocation, anchor)
    }

    func testShelfSortAndReadFiltersUseMetadataWithoutBody() throws {
        var first = try book("B"), second = try book("A")
        first.title = "B"; second.title = "A"
        second.readingLocation = ReadingLocation(chapterID: second.chapters[0].id, utf16Offset: 0)
        second.visibleEndOffset = 100
        let values = [first.metadata, second.metadata]
        XCTAssertEqual(LibraryPolicy.filtered(values, query: "", filter: .all, sort: .title).map(\.id), [second.id, first.id])
        XCTAssertEqual(LibraryPolicy.filtered(values, query: "", filter: .unread, sort: .title).map(\.id), [first.id])
        XCTAssertEqual(LibraryPolicy.filtered(values, query: "", filter: .reading, sort: .title).map(\.id), [second.id])
        XCTAssertEqual(LibraryPolicy.filtered(values, query: " A ", filter: .all, sort: .title).map(\.id), [second.id])
    }

    func testHundredBookCatalogNeverHydratesBodiesAtStartup() throws {
        let f = Fixture(); defer { f.clean() }
        var metadata: [Book] = []
        for index in 0..<100 {
            let chapter = Chapter(id: "stress-chapter-\(index)", title: "压力测试", content: [String(repeating: "长篇压力阅读。", count: 20_000)])
            let value = Book(id: "stress-book-\(index)", title: "压力书籍 \(index)", author: "测试", chapters: [chapter])
            try f.storage.stageContents(of: value)
            metadata.append(value.metadata)
        }
        XCTAssertTrue(f.storage.saveBooks(metadata))
        let started = Date()
        let state = AppState(storage: f.storage, loadsContentsOnDemand: true)
        print("100_BOOK_METADATA_STARTUP_SECONDS=\(Date().timeIntervalSince(started))")
        XCTAssertEqual(state.books.count, 100)
        XCTAssertTrue(state.books.allSatisfy { $0.chapters.isEmpty && !$0.summaries.isEmpty })
        XCTAssertGreaterThan(state.books.reduce(0) { $0 + $1.totalCharacters }, 10_000_000)
    }

    func testPageCacheRespectsBudgetAndMemoryPressure() {
        let page = PageSlice(chapterID: "a", pageIndex: 0, range: NSRange(location: 0, length: 100))
        let stride = MemoryLayout<PageSlice>.stride
        var cache = PageRangeCache<String>(budget: stride * 4, capacity: 3)
        cache.insert([page, page], for: "first")
        cache.insert([page, page], for: "second")
        XCTAssertNotNil(cache.value(for: "first"))
        cache.insert([page, page], for: "third")
        XCTAssertNil(cache.value(for: "second"))
        XCTAssertLessThanOrEqual(cache.estimatedBytes, stride * 4)
        cache.insert(Array(repeating: page, count: 10), for: "oversized")
        XCTAssertNil(cache.value(for: "oversized"))
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
    }


    func testReimportRemovedMissingBodyRepairsAndKeepsReadingRecord() async throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        state.openBook(value); state.prepareReader(size: CGSize(width: 280, height: 400)); state.nextPage()
        let anchor = state.activeBook?.readingLocation
        state.deleteBook(id: value.id)
        try FileManager.default.removeItem(at: f.storage.contentsURL(bookID: value.id))
        let success = await state.importBook(value)
        XCTAssertTrue(success)
        XCTAssertTrue(state.maintenance.removedBooks.isEmpty)
        XCTAssertEqual(state.books.first?.readingLocation, anchor)
        XCTAssertFalse(state.books.first?.chapters.isEmpty ?? true)
    }


    func testRapidBookSwitchingInstallsOnlyFinalBook() async throws {
        let f = Fixture(); defer { f.clean() }
        let first = try book("first"), second = try book("second")
        XCTAssertTrue(f.storage.saveBooks([first, second]))
        let state = AppState(storage: f.storage, loadsContentsOnDemand: true)
        for _ in 0..<20 { state.openBook(state.books[0]); state.openBook(state.books[1]) }
        await state.waitForBookLoad()
        XCTAssertEqual(state.activeBookId, second.id)
        XCTAssertEqual(state.activeBook?.chapters, second.chapters)
        XCTAssertTrue(state.books.first(where: { $0.id == first.id })?.chapters.isEmpty == true)
        XCTAssertFalse(state.isLoadingBook)
    }

    func testUnreadableRecoveryJournalBlocksWritesAndCanBeExported() throws {
        let f = Fixture(); defer { f.clean() }
        let original = try book("original"), other = try book("other")
        XCTAssertTrue(f.storage.saveBooks([original]))
        let catalog = try Data(contentsOf: f.storage.catalogURL)
        let journal = f.storage.directory.appendingPathComponent("restore-journal-v1.json")
        try Data("interrupted damaged journal".utf8).write(to: journal)
        XCTAssertTrue(f.storage.loadBooks().isEmpty)
        XCTAssertFalse(f.storage.saveBooks([other]))
        XCTAssertFalse(f.storage.saveAnnotations([]))
        XCTAssertFalse(f.storage.savePreferences(ReadingPreferences()))
        XCTAssertEqual(try Data(contentsOf: f.storage.catalogURL), catalog)
        XCTAssertTrue(f.storage.recoveryFiles().contains { $0.url == journal })
    }


    func testDraftCanBeSavedAfterOriginalAnnotationWasDeleted() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage)
        XCTAssertTrue(state.addAnnotation(bookID: value.id, chapterID: value.chapters[0].id, range: NSRange(location: 0, length: 3), note: "原笔记"))
        let annotation = try XCTUnwrap(state.annotations.first)
        let draft = NoteDraft(bookID: value.id, chapterID: annotation.chapterID, range: annotation.range, quote: annotation.quote, annotationID: annotation.id, text: "保留的草稿")
        XCTAssertTrue(state.saveDraft(draft))
        state.removeAnnotation(id: annotation.id)
        XCTAssertTrue(state.saveDraftNote(draft, text: draft.text))
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations.first?.note, draft.text)
    }

    func testDraftCannotOverwriteAnUnrelatedAnnotation() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage)
        XCTAssertTrue(state.addAnnotation(bookID: value.id, chapterID: value.chapters[0].id, range: NSRange(location: 0, length: 3), note: "应保留"))
        let annotation = try XCTUnwrap(state.annotations.first)
        let mismatched = NoteDraft(bookID: value.id, chapterID: value.chapters[1].id, range: NSRange(location: 0, length: 3), quote: "第二章", annotationID: annotation.id, text: "不应覆盖")
        XCTAssertFalse(state.saveDraftNote(mismatched, text: mismatched.text))
        XCTAssertEqual(state.annotations.first?.note, "应保留")
    }

}
