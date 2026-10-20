import XCTest
@testable import Interline

@MainActor
final class FeatureTests: XCTestCase {
    private func fixture() -> (ReadingStorage, UserDefaults, String) {
        let name = "InterlineFeatures-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (ReadingStorage(defaults: defaults, directory: directory), defaults, name)
    }
    private func clean(_ storage: ReadingStorage, _ defaults: UserDefaults, _ name: String) {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: storage.directory)
    }
    private func parse(_ text: String) throws -> Book {
        try TXTImportService.parse(data: Data(text.utf8), fileName: "自带小说.txt").book
    }

    func testChineseEnglishChaptersAndPreface() throws {
        let book = try parse("说明文字\r\n\r\n第一章 初见\r\n正文一\r\nChapter 2 Reunion\r\n正文二\r\n尾声\r\n再见")
        XCTAssertEqual(book.chapters.map(\.title), ["正文", "第一章 初见", "Chapter 2 Reunion", "尾声"])
        XCTAssertEqual(book.chapters[0].content, ["说明文字"])
        XCTAssertEqual(book.chapters[1].content, ["正文一"])
        XCTAssertEqual(book.title, "自带小说")
    }

    func testConsecutiveEmptyHeadingsDoNotDuplicateText() throws {
        let book = try parse("第一章\n第二章\n正文")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertTrue(book.chapters[0].content.isEmpty)
        XCTAssertEqual(book.chapters[0].readingText, "第一章")
    }

    func testUTF8BOMAndUTF16Encodings() throws {
        let text = "第一章\n中文与 emoji 🐈"
        let utf8 = try TXTImportService.parse(data: Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8), fileName: "a.txt")
        for (bom, encoding) in [([UInt8(0xFF), 0xFE], String.Encoding.utf16LittleEndian), ([UInt8(0xFE), 0xFF], .utf16BigEndian)] {
            let data = Data(bom) + (try XCTUnwrap(text.data(using: encoding)))
            let parsed = try TXTImportService.parse(data: data, fileName: "a.txt")
            XCTAssertEqual(parsed.book.contentFingerprint, utf8.book.contentFingerprint)
            XCTAssertEqual(parsed.book.chapters.map(\.readingText), utf8.book.chapters.map(\.readingText))
        }
    }

    func testBOMlessUTF16LatinHint() throws {
        let text = "Chapter 1\nHello World"
        let data = try XCTUnwrap(text.data(using: .utf16BigEndian))
        let book = try TXTImportService.parse(data: data, fileName: "a.txt").book
        XCTAssertEqual(book.chapters.first?.content, ["Hello World"])
    }

    func testGB18030AndManualRetry() throws {
        let text = "第一章 遇见\n这是一段简体中文。"
        let encoding = try XCTUnwrap(TextEncodingChoice.gb18030.encoding)
        let data = try XCTUnwrap(text.data(using: encoding))
        XCTAssertThrowsError(try TXTImportService.parse(data: data, fileName: "a.txt", encoding: .utf8))
        let book = try TXTImportService.parse(data: data, fileName: "a.txt", encoding: .gb18030).book
        XCTAssertEqual(book.chapters[0].content, ["这是一段简体中文。"])
    }

    func testIdentityIgnoresFilenameAndLineEndings() throws {
        let a = try TXTImportService.parse(data: Data("第一章\r\n内容".utf8), fileName: "a.txt").book
        let b = try TXTImportService.parse(data: Data("第一章\n内容".utf8), fileName: "b.txt").book
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.chapters.map(\.id), b.chapters.map(\.id))
    }

    func testUnstructuredLongTextIsBoundedWithoutLosingCharacters() throws {
        let text = String(repeating: "长文🐈", count: 18_000)
        let book = try parse(text)
        XCTAssertGreaterThan(book.chapters.count, 1)
        XCTAssertEqual(book.chapters.flatMap(\.content).joined(), text)
        XCTAssertTrue(book.chapters.allSatisfy { $0.content.reduce(0) { $0 + $1.utf16.count } <= 32_000 })
    }

    func testEmptyOversizedAndInvalidTextAreRejected() {
        XCTAssertThrowsError(try TXTImportService.parse(data: Data(" \n\t".utf8), fileName: "a.txt"))
        XCTAssertThrowsError(try TXTImportService.parse(data: Data(repeating: 65, count: TXTImportService.maximumBytes + 1), fileName: "a.txt"))
        XCTAssertThrowsError(try TXTImportService.parse(data: Data([0xFF]), fileName: "a.txt", encoding: .utf8))
        XCTAssertThrowsError(try TXTImportService.parse(data: Data("abc\0def".utf8), fileName: "a.txt", encoding: .utf8))
    }

    func testLocalTXTSourceIsOwnedAfterSourceRemoval() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("第一章\n自己的书".utf8).write(to: url)
        let source = try TXTImportService.read(url: url)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try TXTImportService.parse(data: source.data, fileName: source.fileName).book.chapters[0].content, ["自己的书"])
    }

    func testFullTextSearchUsesCanonicalUTF16Locations() throws {
        let book = try parse("第一章\n前文🐈 Café cafe\n第二章\n另一段 cafe")
        let results = try BookSearchService.search(book: book, query: "CAFE")
        XCTAssertEqual(results.count, 3)
        for result in results {
            let chapter = try XCTUnwrap(book.chapters.first { $0.id == result.chapterID })
            XCTAssertNotNil(Range(result.range, in: chapter.readingText))
            XCTAssertTrue(result.snippet.contains("caf") || result.snippet.contains("Caf"))
        }
    }

    func testSearchLimitEmptyQueryAndUnicodePreview() throws {
        let book = try parse(String(repeating: "猫🐈 Café\n", count: 300))
        XCTAssertEqual(try BookSearchService.search(book: book, query: "猫").count, 200)
        XCTAssertTrue(try BookSearchService.search(book: book, query: "  ").isEmpty)
        XCTAssertTrue(try BookSearchService.search(book: book, query: "不存在").isEmpty)
        XCTAssertFalse(try BookSearchService.search(book: book, query: "🐈")[0].snippet.contains("�"))
    }

    func testFileCatalogMigratesLegacyAndDoesNotEmbedBody() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("第一章\n正文仅在文件中")
        let old = try JSONEncoder().encode([book])
        defaults.set(old, forKey: "interline_saved_books_v1")
        let loaded = storage.loadBooks()
        XCTAssertEqual(loaded.first?.chapters, book.chapters)
        XCTAssertEqual(defaults.data(forKey: "interline_saved_books_v1"), old)
        let catalog = try String(contentsOf: storage.catalogURL, encoding: .utf8)
        XCTAssertFalse(catalog.contains("正文仅在文件中"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.contentsURL(bookID: book.id).path))
    }

    func testFileBackedImportDuplicateAndRelaunch() async throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        storage.saveBooks([])
        let state = AppState(storage: storage)
        let book = try parse("第一章\n" + String(repeating: "导入后阅读🐈。", count: 500))
        let imported = await state.importBook(book)
        XCTAssertTrue(imported)
        let duplicate = await state.importBook(book)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(state.books.count, 1)
        state.openBook(state.books[0])
        state.prepareReader(size: CGSize(width: 300, height: 400))
        await state.waitForPagination()
        state.nextPage()
        let anchor = state.activeBook?.readingLocation
        let next = ReadingStorage(defaults: defaults, directory: storage.directory)
        let relaunched = AppState(storage: next)
        XCTAssertEqual(relaunched.books[0].readingLocation, anchor)
        XCTAssertEqual(relaunched.books[0].chapters, book.chapters)
    }

    func testCancelledReflowNeverReplacesNewBook() async throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let first = try parse(String(repeating: "长篇内容🐈。", count: 6_000))
        let second = try parse("第一章\n第二本书独有内容")
        storage.saveBooks([first, second])
        let state = AppState(storage: storage)
        state.openBook(first)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        state.openBook(second)
        state.prepareReader(size: CGSize(width: 280, height: 380))
        await state.waitForPagination()
        XCTAssertEqual(state.activeBookId, second.id)
        XCTAssertTrue(state.currentPageText.contains("第二本书独有内容"))
        XCTAssertFalse(state.isPaginating)
    }

    func testRapidTypographyChangesAndCloseCancelOldWork() async throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse(String(repeating: "正文很长🐈。", count: 4_000))
        storage.saveBooks([book])
        let state = AppState(storage: storage)
        state.openBook(book)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        state.updatePreferences { $0.fontSize = 25 }
        state.updatePreferences { $0.fontSize = 14 }
        await state.waitForPagination()
        XCTAssertNotNil(state.currentPage)
        XCTAssertEqual(state.preferences.fontSize, 14)
        state.updatePreferences { $0.fontSize = 28 }
        state.closeReader()
        await state.waitForPagination()
        XCTAssertNil(state.pagination)
        XCTAssertFalse(state.isPaginating)
    }

    func testSearchNavigationAndAnnotationPersistence() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("第一章\n前文🐈后文。\n第二章\n搜索目标在这里。")
        storage.saveBooks([book])
        let state = AppState(storage: storage, usesBackgroundLayout: false)
        let match = try XCTUnwrap(BookSearchService.search(book: book, query: "搜索目标").first)
        state.jumpToLocation(bookID: book.id, location: match.location)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        XCTAssertTrue(state.currentPage?.contains(match.range.location) ?? false)
        XCTAssertTrue(state.addAnnotation(bookID: book.id, chapterID: match.chapterID, range: match.range, note: "读到这里"))
        XCTAssertEqual(state.annotations[0].quote, "搜索目标")
        let reloaded = AppState(storage: storage, usesBackgroundLayout: false)
        XCTAssertEqual(reloaded.annotations[0].note, "读到这里")
        state.updateAnnotation(id: state.annotations[0].id, note: "修改后的笔记")
        XCTAssertTrue(state.notesText(for: book.id).contains("修改后的笔记"))
        state.removeAnnotation(id: state.annotations[0].id)
        XCTAssertTrue(storage.loadAnnotations().isEmpty)
    }

    func testAnnotationRejectsSplitSurrogateAndInvalidRanges() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("🐈文字")
        storage.saveBooks([book])
        let chapter = book.chapters[0]
        let range = (chapter.readingText as NSString).range(of: "🐈")
        let state = AppState(storage: storage)
        XCTAssertFalse(state.addAnnotation(bookID: book.id, chapterID: chapter.id, range: NSRange(location: range.location, length: 1)))
        XCTAssertFalse(state.addAnnotation(bookID: book.id, chapterID: chapter.id, range: NSRange(location: Int.max, length: 2)))
        XCTAssertTrue(state.addAnnotation(bookID: book.id, chapterID: chapter.id, range: range))
        XCTAssertTrue(state.addAnnotation(bookID: book.id, chapterID: chapter.id, range: range, note: "同一处更新"))
        XCTAssertEqual(state.annotations.count, 1)
        XCTAssertEqual(state.annotations[0].note, "同一处更新")
    }

    func testPermanentDeletePurgesBodyAndReadingData() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("第一章\n需要删除的内容")
        storage.saveBooks([book])
        let state = AppState(storage: storage, usesBackgroundLayout: false)
        state.openBook(book)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        state.toggleBookmark()
        state.addAnnotation(bookID: book.id, chapterID: book.chapters[0].id, range: NSRange(location: 0, length: 3))
        state.permanentlyDeleteBook(id: book.id)
        XCTAssertTrue(storage.loadBooks().isEmpty)
        XCTAssertNil(storage.loadRecord(bookID: book.id))
        XCTAssertTrue(storage.loadBookmarks().isEmpty)
        XCTAssertTrue(storage.loadAnnotations().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.contentsURL(bookID: book.id).path))
    }

    func testRenamingDoesNotChangeChapterAnchorsOrContentsFile() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("第一章\n原始内容")
        storage.saveBooks([book])
        let before = try Data(contentsOf: storage.contentsURL(bookID: book.id))
        let state = AppState(storage: storage)
        state.updateBookMetadata(id: book.id, title: "新书名", author: "新作者")
        XCTAssertEqual(storage.loadBooks()[0].title, "新书名")
        XCTAssertEqual(try Data(contentsOf: storage.contentsURL(bookID: book.id)), before)
    }

    func testMissingBodyPreservesCatalogEntryAndReportsError() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("第一章\n正文")
        storage.saveBooks([book])
        try FileManager.default.removeItem(at: storage.contentsURL(bookID: book.id))
        let books = storage.loadBooks()
        XCTAssertEqual(books.count, 1)
        XCTAssertTrue(books[0].chapters.isEmpty)
        XCTAssertNotNil(storage.lastError)
    }

    func testReimportRepairsMissingContentAndPreservesAnchor() async throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse("第一章\n" + String(repeating: "需要修复的正文🐈。", count: 300))
        storage.saveBooks([book])
        let state = AppState(storage: storage, usesBackgroundLayout: false)
        state.openBook(book)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        state.nextPage()
        let anchor = state.activeBook?.readingLocation
        try FileManager.default.removeItem(at: storage.contentsURL(bookID: book.id))
        let broken = AppState(storage: storage, usesBackgroundLayout: false)
        XCTAssertTrue(broken.books[0].chapters.isEmpty)
        let repaired = await broken.importBook(book)
        XCTAssertTrue(repaired)
        XCTAssertEqual(broken.books[0].readingLocation, anchor)
        XCTAssertEqual(storage.loadBooks()[0].chapters, book.chapters)
    }

    func testDynamicTypeAndLegacyPreferences() throws {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let book = try parse(String(repeating: "大字号阅读内容。", count: 500))
        storage.saveBooks([book])
        let state = AppState(storage: storage, usesBackgroundLayout: false)
        state.openBook(book)
        state.prepareReader(size: CGSize(width: 300, height: 400), scale: 1)
        let normalCount = try XCTUnwrap(state.pagination).pages.count
        state.prepareReader(size: CGSize(width: 300, height: 400), scale: 1.7)
        XCTAssertGreaterThan(try XCTUnwrap(state.pagination).pages.count, normalCount)
        state.updatePreferences { $0.usesDynamicType = false }
        XCTAssertEqual(try XCTUnwrap(state.pagination).pages.count, normalCount)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ReadingPreferences())) as? [String: Any])
        legacy.removeValue(forKey: "usesDynamicType")
        legacy.removeValue(forKey: "followsSystemAppearance")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "interline_saved_preferences_v1")
        XCTAssertEqual(storage.loadPreferences().fontSize, 17)
    }

    func testContentFileNameCannotEscapeStorageDirectory() {
        let (storage, defaults, name) = fixture()
        defer { clean(storage, defaults, name) }
        let url = storage.contentsURL(bookID: "../../elsewhere")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Contents")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent(), storage.directory)
    }
}
