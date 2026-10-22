import XCTest
@testable import Interline

private actor DetailReadGate {
    private var entered = false
    private var opened = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func hold() async {
        guard !opened else { return }
        entered = true; arrival?.resume(); arrival = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func open() { opened = true; release?.resume(); release = nil }
}

@MainActor
final class PageOperationTests: XCTestCase {
    @MainActor private struct Fixture {
        let name: String
        let defaults: UserDefaults
        let storage: ReadingStorage
        let state: AppState
        let book: Book
        init() {
            let name = "PageOperation-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: name)!
            let storage = ReadingStorage(defaults: defaults, directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            let book = Book(id: "original", title: "原书名", author: "作者", chapters: [Chapter(id: "c", title: "章节", content: ["用于验证错误反馈和重试的原文。"] )])
            let seeded = storage.saveBooks([book])
            self.name = name; self.defaults = defaults; self.storage = storage; self.book = book
            self.state = AppState(storage: storage, usesBackgroundLayout: false)
            XCTAssertTrue(seeded)
        }
        func clean() { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: storage.directory) }
        func block(_ url: URL) throws -> URL {
            let retained = url.appendingPathExtension("retained")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.moveItem(at: url, to: retained) }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return retained
        }
        func unblock(_ url: URL, retained: URL) throws {
            try FileManager.default.removeItem(at: url)
            if FileManager.default.fileExists(atPath: retained.path) { try FileManager.default.moveItem(at: retained, to: url) }
        }
    }

    func testMetadataFailureReturnsReasonPreservesOriginalAndRetries() throws {
        let f = Fixture(); defer { f.clean() }
        let original = try Data(contentsOf: f.storage.catalogURL)
        let retained = try f.block(f.storage.catalogURL)
        let result = f.state.updateBookMetadata(id: f.book.id, title: "重试后的书名", author: "新作者")
        XCTAssertNotNil(result.errorMessage)
        XCTAssertEqual(f.state.books.first?.title, f.book.title)
        XCTAssertEqual(try Data(contentsOf: retained), original)
        try f.unblock(f.storage.catalogURL, retained: retained)
        XCTAssertEqual(f.state.updateBookMetadata(id: f.book.id, title: "重试后的书名", author: "新作者"), .success)
        XCTAssertEqual(AppState(storage: f.storage).books.first?.title, "重试后的书名")
    }

    func testRemovalFailureDoesNotPublishRemovalAndRetryCommits() throws {
        let f = Fixture(); defer { f.clean() }
        let original = try Data(contentsOf: f.storage.catalogURL)
        let retained = try f.block(f.storage.catalogURL)
        XCTAssertNotNil(f.state.deleteBook(id: f.book.id).errorMessage)
        XCTAssertEqual(f.state.books.map(\.id), [f.book.id])
        XCTAssertTrue(f.state.maintenance.removedBooks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: retained), original)
        try f.unblock(f.storage.catalogURL, retained: retained)
        XCTAssertEqual(f.state.deleteBook(id: f.book.id), .success)
        let relaunched = AppState(storage: f.storage)
        XCTAssertTrue(relaunched.books.isEmpty)
        XCTAssertEqual(relaunched.maintenance.removedBooks.map(\.id), [f.book.id])
    }

    func testPendingPermanentCleanupIsFailureAndSameOperationCanRetry() throws {
        let f = Fixture(); defer { f.clean() }
        let url = f.storage.directory.appendingPathComponent("annotations-v1.json")
        let retained = try f.block(url)
        XCTAssertNotNil(f.state.permanentlyDeleteBook(id: f.book.id).errorMessage)
        XCTAssertTrue(f.state.books.isEmpty)
        XCTAssertEqual(f.state.maintenance.pendingDeletions.map(\.id), [f.book.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.storage.contentsURL(bookID: f.book.id).path))
        try f.unblock(url, retained: retained)
        XCTAssertEqual(f.state.permanentlyDeleteBook(id: f.book.id), .success)
        XCTAssertTrue(f.state.maintenance.pendingDeletions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.storage.contentsURL(bookID: f.book.id).path))
        XCTAssertTrue(AppState(storage: f.storage).maintenance.pendingDeletions.isEmpty)
    }

    func testNoteDeletionFailureRetainsNoteThenRetryPersists() throws {
        let f = Fixture(); defer { f.clean() }
        XCTAssertTrue(f.state.addAnnotation(bookID: f.book.id, chapterID: "c", range: NSRange(location: 0, length: 2), note: "必须保留"))
        let id = try XCTUnwrap(f.state.annotations.first?.id)
        let url = f.storage.directory.appendingPathComponent("annotations-v1.json")
        let original = try Data(contentsOf: url)
        let retained = try f.block(url)
        XCTAssertNotNil(f.state.removeAnnotation(id: id).errorMessage)
        XCTAssertEqual(f.state.annotations.first?.note, "必须保留")
        XCTAssertEqual(try Data(contentsOf: retained), original)
        try f.unblock(url, retained: retained)
        XCTAssertEqual(f.state.removeAnnotation(id: id), .success)
        XCTAssertTrue(f.storage.loadAnnotations().isEmpty)
    }

    func testBookmarkDeletionReportsPreservationFailureAndCanRetry() throws {
        let f = Fixture(); defer { f.clean() }
        f.state.openBook(f.book)
        f.state.prepareReader(size: CGSize(width: 300, height: 400))
        f.state.toggleBookmark()
        let id = try XCTUnwrap(f.state.bookmarks.first?.id)
        let key = "interline_saved_bookmarks_v1"
        let damaged = Data("broken bookmark bytes".utf8)
        f.defaults.set(damaged, forKey: key)
        let recovery = f.storage.directory.appendingPathComponent("Recovery")
        try Data("blocked".utf8).write(to: recovery)
        XCTAssertNotNil(f.state.removeBookmark(id: id).errorMessage)
        XCTAssertEqual(f.state.bookmarks.count, 1)
        XCTAssertEqual(f.defaults.data(forKey: key), damaged)
        try FileManager.default.removeItem(at: recovery)
        XCTAssertEqual(f.state.removeBookmark(id: id), .success)
        XCTAssertTrue(f.storage.loadBookmarks().isEmpty)
        XCTAssertFalse(f.storage.recoveryFiles().isEmpty)
    }

    func testBusyInvalidAndMissingTargetsDoNotClaimSuccessOrMutateCatalog() throws {
        let f = Fixture(); defer { f.clean() }
        let original = try Data(contentsOf: f.storage.catalogURL)
        XCTAssertNotNil(f.state.updateBookMetadata(id: f.book.id, title: " ", author: "").errorMessage)
        XCTAssertNotNil(f.state.updateBookMetadata(id: "missing", title: "x", author: "").errorMessage)
        f.state.isMaintenanceBusy = true
        XCTAssertNotNil(f.state.updateBookMetadata(id: f.book.id, title: "错误更新", author: "").errorMessage)
        XCTAssertNotNil(f.state.deleteBook(id: f.book.id).errorMessage)
        XCTAssertNotNil(f.state.permanentlyDeleteBook(id: f.book.id).errorMessage)
        XCTAssertNotNil(f.state.retryPendingDeletions().errorMessage)
        XCTAssertEqual(try Data(contentsOf: f.storage.catalogURL), original)
        XCTAssertEqual(f.state.books.first?.title, f.book.title)
    }

    func testCancelledDetailsReadDoesNotMarkContentsUnavailable() async {
        let f = Fixture(); defer { f.clean() }
        f.state.books = f.state.books.map(\.metadata)
        let gate = DetailReadGate()
        f.state.contentsLoader = BookContentsLoader(beforeRead: { await gate.hold() })
        let task = Task { try await f.state.details(for: f.book.metadata) }
        await gate.waitForEntry()
        task.cancel(); await gate.open()
        do { _ = try await task.value; XCTFail("Cancelled read must not return a successful load") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(f.state.books.first?.contentsUnavailable == true)
        XCTAssertFalse(f.state.notice?.isError == true)
    }

    func testFileCancellationChecksDomainAndDoesNotHideProviderFailure() {
        XCTAssertNil(FileOperationFailure.message(for: CancellationError(), operation: "导出"))
        XCTAssertNil(FileOperationFailure.message(for: CocoaError(.userCancelled), operation: "导出"))
        let provider = NSError(domain: "ExampleProvider", code: CocoaError.Code.userCancelled.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "提供器无法保存"])
        let message = FileOperationFailure.message(for: provider, operation: "笔记导出")
        XCTAssertTrue(message?.contains("提供器无法保存") == true)
        XCTAssertTrue(message?.contains("笔记导出") == true)
        XCTAssertNotNil(FileOperationFailure.message(for: CocoaError(.fileWriteOutOfSpace), operation: "正文导出"))
    }
}
