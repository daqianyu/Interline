import XCTest
@testable import Interline

private actor DraftWriteProbe {
    var calls = 0
    func record() { calls += 1 }
}

private actor DraftWriteGate {
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
final class DraftPersistenceTests: XCTestCase {
    @MainActor private struct Fixture {
        let name = "DraftPersistence-" + UUID().uuidString
        let defaults: UserDefaults
        let storage: ReadingStorage
        let state: AppState
        init() {
            defaults = UserDefaults(suiteName: name)!
            storage = ReadingStorage(defaults: defaults,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            state = AppState(storage: storage, usesBackgroundLayout: false)
        }
        func draft(_ text: String = "draft") -> NoteDraft {
            let book = state.books[0], chapter = book.chapters[0]
            return NoteDraft(bookID: book.id, chapterID: chapter.id, range: NSRange(location: 0, length: 1),
                             quote: (chapter.readingText as NSString).substring(to: 1), text: text)
        }
        func clean() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: storage.directory)
        }
    }

    func testRapidInputCoalescesAndWritesOffMainThread() async {
        let f = Fixture(); defer { f.clean() }
        let probe = DraftWriteProbe()
        f.storage.draftWriteOperation = { drafts, directory in
            try await Task.detached {
                XCTAssertFalse(Thread.isMainThread)
                try DraftFileWriter.write(drafts, directory: directory)
            }.value
            await probe.record()
        }
        var draft = f.draft()
        for index in 0..<100 {
            draft.text = "version \(index)"
            XCTAssertTrue(f.state.queueDraft(draft))
        }
        XCTAssertTrue(f.state.drafts.isEmpty)
        XCTAssertEqual(f.state.draftSaveState(for: draft.id), .saving)
        let success = await f.state.flushDrafts()
        XCTAssertTrue(success)
        let calls = await probe.calls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, "version 99")
        XCTAssertEqual(AppState(storage: f.storage).draft(for: draft.id)?.text, "version 99")
        XCTAssertEqual(f.state.draftSaveState(for: draft.id), .saved)
    }

    func testInputDuringWriteKeepsNewVersionAndExcludesMaintenance() async throws {
        let f = Fixture(); defer { f.clean() }
        let gate = DraftWriteGate()
        f.storage.draftWriteOperation = { drafts, directory in
            await gate.hold()
            try await Task.detached { try DraftFileWriter.write(drafts, directory: directory) }.value
        }
        var draft = f.draft("old")
        XCTAssertTrue(f.state.queueDraft(draft))
        let saving = Task { await f.state.flushDrafts() }
        await gate.waitForEntry()
        XCTAssertTrue(f.storage.isWritingDrafts)
        XCTAssertFalse(f.storage.saveDrafts([]))
        XCTAssertThrowsError(try f.storage.beginTransaction())
        XCTAssertFalse(f.state.removeDraft(id: draft.id))
        XCTAssertFalse(f.state.saveDraftNote(draft, text: "not yet"))
        f.state.permanentlyDeleteBook(id: draft.bookID)
        XCTAssertTrue(f.state.books.contains { $0.id == draft.bookID })
        draft.text = "newest"
        XCTAssertTrue(f.state.queueDraft(draft))
        XCTAssertEqual(f.state.draft(for: draft.id)?.text, "newest")
        XCTAssertEqual(f.state.draftSaveState(for: draft.id), .saving)
        await gate.open()
        let success = await saving.value
        XCTAssertTrue(success)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, "newest")
        XCTAssertEqual(f.state.draftSaveState(for: draft.id), .saved)
        XCTAssertFalse(f.storage.isWritingDrafts)
        try f.storage.beginTransaction()
        try f.storage.commitTransaction()
    }

    func testFailedWriteKeepsInputAndCanRetry() async throws {
        let f = Fixture(); defer { f.clean() }
        let url = f.storage.directory.appendingPathComponent("drafts-v1.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let draft = f.draft("keep every character")
        XCTAssertTrue(f.state.queueDraft(draft))
        let failed = await f.state.flushDrafts()
        XCTAssertFalse(failed)
        XCTAssertTrue(f.state.drafts.isEmpty)
        XCTAssertEqual(f.state.draft(for: draft.id)?.text, draft.text)
        XCTAssertEqual(f.state.draftSaveState(for: draft.id), .failed)
        XCTAssertFalse(f.state.removeDraft(id: draft.id))
        try FileManager.default.removeItem(at: url)
        let retried = await f.state.flushDrafts()
        XCTAssertTrue(retried)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, draft.text)
        XCTAssertEqual(f.state.draftSaveState(for: draft.id), .saved)
    }

    func testCommittedNoteDoesNotResurrectRemovedDraft() async {
        let f = Fixture(); defer { f.clean() }
        let draft = f.draft("committed note")
        XCTAssertTrue(f.state.queueDraft(draft))
        let flushed = await f.state.flushDrafts()
        XCTAssertTrue(flushed)
        XCTAssertTrue(f.state.saveDraftNote(draft, text: draft.text))
        XCTAssertTrue(f.state.removeDraft(id: draft.id))
        let again = await f.state.flushDrafts()
        XCTAssertTrue(again)
        XCTAssertTrue(f.storage.loadDrafts().isEmpty)
        let relaunched = AppState(storage: f.storage)
        XCTAssertTrue(relaunched.drafts.isEmpty)
        XCTAssertEqual(relaunched.annotations.first?.note, draft.text)
    }

    func testBackupFlushesPendingInputAndFailedFlushPreventsExport() async throws {
        let f = Fixture(); defer { f.clean() }
        var draft = f.draft("included in backup")
        XCTAssertTrue(f.state.queueDraft(draft))
        let data = try await f.state.exportLibraryBackup()
        XCTAssertEqual(try ReadingStorage.decodeBackup(data).drafts.first?.text, draft.text)
        let url = f.storage.directory.appendingPathComponent("drafts-v1.json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        draft.text = "not on disk"
        XCTAssertTrue(f.state.queueDraft(draft))
        do { _ = try await f.state.exportLibraryBackup(); XCTFail("Export must not omit unsaved input") }
        catch { }
        let restored = await f.state.restoreLibraryBackup(data)
        XCTAssertFalse(restored)
        XCTAssertEqual(f.state.draft(for: draft.id)?.text, "not on disk")
        XCTAssertFalse(f.state.isMaintenanceBusy)
    }

    func testBackgroundWritePreservesCorruptBytesAndRefusesUnsafeReplacement() async throws {
        let f = Fixture(); defer { f.clean() }
        let url = f.storage.directory.appendingPathComponent("drafts-v1.json")
        let damaged = Data("original broken draft bytes".utf8)
        try damaged.write(to: url)
        let recovery = f.storage.directory.appendingPathComponent("Recovery")
        try Data("blocked".utf8).write(to: recovery)
        let draft = f.draft()
        XCTAssertTrue(f.state.queueDraft(draft))
        let failed = await f.state.flushDrafts()
        XCTAssertFalse(failed)
        XCTAssertEqual(try Data(contentsOf: url), damaged)
        try FileManager.default.removeItem(at: recovery)
        let success = await f.state.flushDrafts()
        XCTAssertTrue(success)
        let archive = try XCTUnwrap(f.storage.recoveryFiles().first)
        XCTAssertEqual(try Data(contentsOf: archive.url), damaged)
        XCTAssertEqual(f.storage.loadDrafts().first?.text, draft.text)
    }

    func testMaintenanceBlocksNewInputUntilExistingFlushCompletes() async throws {
        let f = Fixture(); defer { f.clean() }
        let gate = DraftWriteGate()
        f.storage.draftWriteOperation = { drafts, directory in
            await gate.hold()
            try await Task.detached { try DraftFileWriter.write(drafts, directory: directory) }.value
        }
        var draft = f.draft("before export")
        XCTAssertTrue(f.state.queueDraft(draft))
        let exporting = Task { try await f.state.exportLibraryBackup() }
        await gate.waitForEntry()
        XCTAssertTrue(f.state.isMaintenanceBusy)
        draft.text = "during export"
        XCTAssertFalse(f.state.queueDraft(draft))
        XCTAssertEqual(f.state.draft(for: draft.id)?.text, "before export")
        await gate.open()
        let data = try await exporting.value
        XCTAssertEqual(try ReadingStorage.decodeBackup(data).drafts.first?.text, "before export")
        XCTAssertFalse(f.state.isMaintenanceBusy)
    }

    func testBatchKeepsIndependentDraftsAndClearsEmptyInput() async {
        let f = Fixture(); defer { f.clean() }
        let first = f.draft("first")
        var other = f.draft("other")
        other.id += "-other"
        XCTAssertTrue(f.state.saveDraft(other))
        XCTAssertTrue(f.state.queueDraft(first))
        other.text = ""
        XCTAssertTrue(f.state.queueDraft(other))
        let success = await f.state.flushDrafts()
        XCTAssertTrue(success)
        XCTAssertEqual(f.storage.loadDrafts().map(\.id), [first.id])
        XCTAssertEqual(f.state.draftSaveState(for: other.id), .saved)
        XCTAssertNil(f.state.draft(for: other.id))
    }
}
