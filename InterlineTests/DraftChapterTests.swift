import XCTest
@testable import Interline

private actor ChapterReadGate {
    private var entered = false
    private var opened = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func hold() async {
        guard !opened else { return }
        entered = true
        arrival?.resume(); arrival = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func open() { opened = true; release?.resume(); release = nil }
}

@MainActor
final class DraftChapterTests: XCTestCase {
    @MainActor private struct Fixture {
        let name = "DraftChapter-" + UUID().uuidString
        let defaults: UserDefaults
        let storage: ReadingStorage
        let state: AppState
        let book: Book
        let draft: NoteDraft
        init() {
            defaults = UserDefaults(suiteName: name)!
            storage = ReadingStorage(defaults: defaults,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            book = Book(id: "target", title: "目标", author: "作者", chapters: [
                Chapter(id: "chapter", title: "👩🏽‍💻", content: [String(repeating: "原文 e\u{301}。", count: 1000)])
            ])
            let other = Book(id: "other", title: "另一本", author: "作者", chapters: [
                Chapter(id: "chapter", title: "另一本", content: ["不同原文"])
            ])
            let seeded = storage.saveBooks([book, other])
            XCTAssertTrue(seeded)
            state = AppState(storage: storage, usesBackgroundLayout: false)
            state.books = state.books.map(\.metadata)
            draft = NoteDraft(bookID: book.id, chapterID: "chapter", range: NSRange(location: 0, length: "👩🏽‍💻".utf16.count),
                quote: "👩🏽‍💻", text: "保留的输入")
            XCTAssertTrue(state.saveDraft(draft))
        }
        func gate() -> ChapterReadGate {
            let gate = ChapterReadGate()
            state.contentsLoader = BookContentsLoader(beforeRead: {
                XCTAssertFalse(Thread.isMainThread)
                await gate.hold()
            })
            return gate
        }
        func clean() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: storage.directory)
        }
    }

    func testBackgroundReadTargetsDraftAfterReaderSwitchAndPersists() async {
        let f = Fixture(); defer { f.clean() }
        let gate = f.gate()
        let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: "最终输入") }
        await gate.waitForEntry()
        // Main actor remains responsive while the contents actor is occupied.
        f.state.activeBookId = "other"
        await gate.open()
        let success = await task.value
        XCTAssertTrue(success)
        XCTAssertEqual(f.state.activeBookId, "other")
        XCTAssertTrue(f.state.books.allSatisfy { $0.chapters.isEmpty })
        XCTAssertEqual(f.storage.loadAnnotations().first?.bookID, f.book.id)
        XCTAssertEqual(f.storage.loadAnnotations().first?.quote, f.draft.quote)
        XCTAssertTrue(f.state.removeDraft(id: f.draft.id))
        let relaunched = AppState(storage: f.storage)
        XCTAssertEqual(relaunched.annotations.first?.note, "最终输入")
        XCTAssertTrue(relaunched.drafts.isEmpty)
    }

    func testCancelledReadDoesNotWriteOrRemoveDraft() async {
        let f = Fixture(); defer { f.clean() }
        let gate = f.gate()
        let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: "不能写入") }
        await gate.waitForEntry()
        task.cancel()
        await gate.open()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, f.draft.text)
        XCTAssertFalse(f.state.notice?.isError == true)
    }

    func testChangedOrDiscardedDraftInvalidatesInFlightCommit() async {
        let f = Fixture(); defer { f.clean() }
        for discard in [false, true] {
            let gate = f.gate()
            let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: "过期输入") }
            await gate.waitForEntry()
            if discard { XCTAssertTrue(f.state.removeDraft(id: f.draft.id)) }
            else {
                var newer = f.draft
                newer.text = "另一次编辑的最新输入"
                newer.updatedAt = Date()
                XCTAssertTrue(f.state.saveDraft(newer))
            }
            await gate.open()
            let success = await task.value
            XCTAssertFalse(success)
            XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
            if discard { XCTAssertTrue(f.storage.loadDrafts().isEmpty) }
            else { XCTAssertEqual(f.storage.loadDrafts().first?.text, "另一次编辑的最新输入") }
        }
    }

    func testRemovedBookKeepsDraftTarget() async {
        let f = Fixture(); defer { f.clean() }
        let gate = f.gate()
        let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text) }
        await gate.waitForEntry()
        f.state.deleteBook(id: f.book.id)
        await gate.open()
        let success = await task.value
        XCTAssertTrue(success)
        XCTAssertEqual(f.state.maintenance.removedBooks.first?.id, f.book.id)
        XCTAssertEqual(f.storage.loadAnnotations().first?.bookID, f.book.id)
    }

    func testPermanentDeletionCannotResurrectNoteOrDraft() async {
        let f = Fixture(); defer { f.clean() }
        let gate = f.gate()
        let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text) }
        await gate.waitForEntry()
        f.state.permanentlyDeleteBook(id: f.book.id)
        await gate.open()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
        XCTAssertTrue(f.storage.loadDrafts().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.storage.contentsURL(bookID: f.book.id).path))
    }

    func testCompletedMaintenanceInvalidatesOldReadAndRetrySucceeds() async throws {
        let f = Fixture(); defer { f.clean() }
        let gate = f.gate()
        let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text) }
        await gate.waitForEntry()
        _ = try await f.state.exportLibraryBackupFile()
        XCTAssertFalse(f.state.isMaintenanceBusy)
        await gate.open()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, f.draft.text)
        let retried = await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text)
        XCTAssertTrue(retried)
    }

    func testCompletedImportInvalidatesOldRead() async {
        let f = Fixture(); defer { f.clean() }
        let gate = f.gate()
        let task = Task { await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text) }
        await gate.waitForEntry()
        let imported = Book(id: "imported", title: "新书", author: "作者", chapters: [Chapter(id: "c", title: "标题", content: ["正文"])])
        let importedOK = await f.state.importBook(imported)
        XCTAssertTrue(importedOK)
        await gate.open()
        let success = await task.value
        XCTAssertFalse(success)
        XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, f.draft.text)
    }

    func testCorruptOrMissingChapterAndInvalidQuoteKeepDraft() async throws {
        let f = Fixture(); defer { f.clean() }
        let url = f.storage.contentsURL(bookID: f.book.id)
        let original = try Data(contentsOf: url)
        for bytes in [Data("broken".utf8), try JSONEncoder().encode([Chapter(id: "absent", title: "空", content: [])])] {
            try bytes.write(to: url)
            let success = await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text)
            XCTAssertFalse(success)
            XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
            XCTAssertEqual(f.storage.loadDrafts().first?.text, f.draft.text)
        }
        try FileManager.default.removeItem(at: url)
        let missing = await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text)
        XCTAssertFalse(missing)
        try original.write(to: url)
        for (range, quote) in [(f.draft.range, "不匹配"), (NSRange(location: 0, length: 2), "👩"), (NSRange(location: Int.max, length: 1), "x")] {
            let invalid = NoteDraft(bookID: f.book.id, chapterID: "chapter", range: range, quote: quote)
            let success = await f.state.saveDraftNoteAsync(invalid, text: "不能写入")
            XCTAssertFalse(success)
            XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
        }
        XCTAssertEqual(f.storage.loadDrafts().first?.text, f.draft.text)
    }

    func testEditingRevalidatesIdentityAndDeletedAnnotationCanBeRecreated() async throws {
        let f = Fixture(); defer { f.clean() }
        let saved = await f.state.saveDraftNoteAsync(f.draft, text: "原笔记")
        XCTAssertTrue(saved)
        let original = try XCTUnwrap(f.state.annotations.first)
        let edited = NoteDraft(bookID: f.book.id, chapterID: f.draft.chapterID,
            range: f.draft.range, quote: f.draft.quote, annotationID: original.id)
        let updated = await f.state.saveDraftNoteAsync(edited, text: "修改后的笔记")
        XCTAssertTrue(updated)
        XCTAssertEqual(f.state.annotations.first?.id, original.id)
        let unrelated = NoteDraft(bookID: "other", chapterID: "chapter", range: NSRange(location: 0, length: 1), quote: "另", annotationID: original.id)
        let rejected = await f.state.saveDraftNoteAsync(unrelated, text: "不应覆盖")
        XCTAssertFalse(rejected)
        XCTAssertEqual(f.storage.loadAnnotations().first?.note, "修改后的笔记")
        f.state.removeAnnotation(id: original.id)
        let recreated = await f.state.saveDraftNoteAsync(edited, text: "从草稿恢复")
        XCTAssertTrue(recreated)
        XCTAssertEqual(f.storage.loadAnnotations().first?.note, "从草稿恢复")
        XCTAssertNotEqual(f.storage.loadAnnotations().first?.id, original.id)
    }

    func testCachedChapterDoesNotReadDiskAndWriteFailureKeepsInput() async throws {
        let f = Fixture(); defer { f.clean() }
        f.state.books[0].chapters = f.book.chapters
        f.state.contentsLoader = BookContentsLoader(beforeRead: { XCTFail("Cached chapter must not read disk") })
        let url = f.storage.directory.appendingPathComponent("annotations-v1.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let failed = await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text)
        XCTAssertFalse(failed)
        XCTAssertTrue(f.state.annotations.isEmpty)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, f.draft.text)
        try FileManager.default.removeItem(at: url)
        let retried = await f.state.saveDraftNoteAsync(f.draft, text: f.draft.text)
        XCTAssertTrue(retried)
    }
}
