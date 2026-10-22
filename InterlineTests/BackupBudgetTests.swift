import XCTest
@testable import Interline

final class BackupBudgetTests: XCTestCase {
    private struct Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupBudget-" + UUID().uuidString)
        init() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        func url(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }
        func clean() { try? FileManager.default.removeItem(at: directory) }
        func stage(_ book: Book) throws { try JSONEncoder().encode(book.chapters).write(to: url(book.id), options: .atomic) }
        func encode(_ books: [Book], removed: [Book] = [], notes: [ReadingAnnotation] = [], drafts: [NoteDraft] = [],
                    limit: Int = ReadingStorage.maximumBackupBytes) throws -> Data {
            try V1BackupWriter.encode(books: books, removedBooks: removed, preferences: ReadingPreferences(),
                                      bookmarks: [], annotations: notes, drafts: drafts,
                                      createdAt: Date(timeIntervalSinceReferenceDate: 123), maximumBytes: limit,
                                      contentsURL: { url($0) })
        }
    }

    private func book(_ id: String = "a") -> Book {
        Book(id: id, title: "中文\"书名" + id, author: "作者", chapters: [
            Chapter(id: "chapter", title: "第一章", content: ["中英文 👩🏽‍💻 café e\u{301}", "\"斜线\\\n\t\u{0}结尾"])
        ], lastReadDate: Date(timeIntervalSinceReferenceDate: 42))
    }

    func testIncrementalJSONMatchesLegacySchemaAndPreservesAllFields() throws {
        let f = try Fixture(); defer { f.clean() }
        var active = book(), removed = book("removed")
        active.currentChapterIndex = 0; active.currentPageIndex = 2
        active.readingLocation = ReadingLocation(chapterID: "chapter", utf16Offset: 8)
        active.visibleEndOffset = 20
        removed.contentsUnavailable = false
        let note = ReadingAnnotation(bookID: active.id, chapterID: "chapter", range: NSRange(location: 0, length: 3), quote: "第一章", note: "笔记\n\"内容")
        let draft = NoteDraft(bookID: removed.id, chapterID: "chapter", range: NSRange(location: 0, length: 3), quote: "第一章", text: "草稿 👋")
        try f.stage(active); try f.stage(removed)
        let data = try f.encode([active.metadata], removed: [removed.metadata], notes: [note], drafts: [draft])
        // Decode through the public v1 path, independent of the incremental writer.
        let decoded = try ReadingStorage.decodeBackup(data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSinceReferenceDate: 123))
        XCTAssertEqual(decoded.books, [active])
        XCTAssertEqual(decoded.removedBooks, [removed])
        XCTAssertEqual(decoded.annotations, [note])
        XCTAssertEqual(decoded.drafts.first?.text, draft.text)
        let legacy = LibraryBackup(version: 1, createdAt: decoded.createdAt, books: [active], removedBooks: [removed],
                                   preferences: ReadingPreferences(), bookmarks: [], annotations: [note], drafts: [draft])
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? NSDictionary)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        XCTAssertEqual(actual, expected)
    }

    func testPreflightChecksAllFileSizesBeforeDecodingAnyBody() throws {
        let f = try Fixture(); defer { f.clean() }
        let first = book("broken"), second = book("large")
        let damaged = Data("not JSON".utf8)
        try damaged.write(to: f.url(first.id))
        try Data(repeating: 0x20, count: 2_000).write(to: f.url(second.id))
        XCTAssertThrowsError(try f.encode([first.metadata, second.metadata], limit: 1_000)) { error in
            XCTAssertTrue(error is LibraryBackupError, "Must reject budget before attempting the first broken JSON")
        }
        XCTAssertEqual(try Data(contentsOf: f.url(first.id)), damaged)
    }

    func testExactOutputBoundaryIncludesEscapingAndClosingDelimiter() throws {
        let f = try Fixture(); defer { f.clean() }
        var value = book()
        value.chapters[0].content = [String(repeating: "\u{0}\"\\", count: 100)]
        value.updateChapterSummaries()
        let expected = try f.encode([value])
        let exact = try f.encode([value], limit: expected.count)
        XCTAssertEqual(try ReadingStorage.decodeBackup(exact).books, [value])
        XCTAssertThrowsError(try f.encode([value], limit: expected.count - 1)) { XCTAssertTrue($0 is LibraryBackupError) }
        XCTAssertThrowsError(try f.encode([value], limit: 0)) { XCTAssertTrue($0 is LibraryBackupError) }
    }

    func testMissingDirectoryAndSymbolicLinkBodiesAreRejected() throws {
        let f = try Fixture(); defer { f.clean() }
        let value = book()
        XCTAssertThrowsError(try f.encode([value.metadata]))
        try FileManager.default.createDirectory(at: f.url(value.id), withIntermediateDirectories: false)
        XCTAssertThrowsError(try f.encode([value.metadata]))
        try FileManager.default.removeItem(at: f.url(value.id))
        let original = f.url("original")
        let bytes = try JSONEncoder().encode(value.chapters)
        try bytes.write(to: original)
        try FileManager.default.createSymbolicLink(at: f.url(value.id), withDestinationURL: original)
        XCTAssertThrowsError(try f.encode([value.metadata]))
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testInvalidBodiesAndMismatchedQuotesCannotProduceSuccessfulBackup() throws {
        let f = try Fixture(); defer { f.clean() }
        let value = book()
        for bytes in [Data("broken".utf8), Data("[]".utf8), try JSONEncoder().encode([value.chapters[0], value.chapters[0]])] {
            try bytes.write(to: f.url(value.id), options: .atomic)
            XCTAssertThrowsError(try f.encode([value.metadata]))
            XCTAssertEqual(try Data(contentsOf: f.url(value.id)), bytes)
        }
        try f.stage(value)
        let note = ReadingAnnotation(bookID: value.id, chapterID: "chapter", range: NSRange(location: 0, length: 3), quote: "不匹配")
        XCTAssertThrowsError(try f.encode([value.metadata], notes: [note]))
        XCTAssertThrowsError(try f.encode([value], removed: [value]))
    }

    func testManyOnDemandBooksRemainCompleteAndOrdered() throws {
        let f = try Fixture(); defer { f.clean() }
        let values = (0..<20).map { book("book-\($0)") }
        for value in values { try f.stage(value) }
        let data = try f.encode(Array(values.prefix(12)).map(\.metadata), removed: Array(values.suffix(8)).map(\.metadata))
        let decoded = try ReadingStorage.decodeBackup(data)
        XCTAssertEqual(decoded.books, Array(values.prefix(12)))
        XCTAssertEqual(decoded.removedBooks, Array(values.suffix(8)))
    }

    func testBoundedReaderAcceptsExactBytesAndRejectsOversize() throws {
        let f = try Fixture(); defer { f.clean() }
        let bytes = Data(repeating: 0x61, count: 70_000)
        let url = f.url("input")
        try bytes.write(to: url)
        XCTAssertEqual(try BoundedBackupInput.read(url, maximumBytes: bytes.count), bytes)
        XCTAssertThrowsError(try BoundedBackupInput.read(url, maximumBytes: bytes.count - 1)) { XCTAssertTrue($0 is LibraryBackupError) }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    @MainActor func testCallerCancellationReachesBackgroundExport() async throws {
        let f = try Fixture(); defer { f.clean() }
        let name = "BackupCancel-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let storage = ReadingStorage(defaults: defaults, directory: f.directory)
        let value = book()
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await storage.buildBackup(books: [value], maintenance: LibraryMaintenanceState(),
                                                  preferences: ReadingPreferences(), bookmarks: [], annotations: [], drafts: [])
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).isEmpty)
    }
}
