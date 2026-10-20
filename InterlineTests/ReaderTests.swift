import XCTest
import CoreText
@testable import Interline

@MainActor
final class ReaderTests: XCTestCase {
    private let canvas = CGSize(width: 300, height: 420)

    private func chapter(_ id: String = "chapter-1") -> Chapter {
        Chapter(id: id, title: "第一章 · 测试", content: Array(repeating:
            "长篇中文排版，包含标点、English 123、𠮷、👨‍👩‍👧‍👦与组合字符e\u{301}。每一页都应该连续，不丢失文字。", count: 80))
    }

    private func withStorage(_ action: (ReadingStorage, UserDefaults) throws -> Void) rethrows {
        let suite = "InterlineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try action(ReadingStorage(defaults: defaults), defaults)
    }

    private func makeState(storage: ReadingStorage, chapters: [Chapter]? = nil) -> AppState {
        let book = Book(id: "test-book", title: "测试书", author: "测试", chapters: chapters ?? [chapter(), chapter("chapter-2")])
        storage.saveBooks([book])
        let state = AppState(storage: storage)
        state.openBook(state.books[0])
        state.prepareReader(size: canvas)
        return state
    }

    func testPaginationCoversEveryUTF16UnitExactlyOnce() throws {
        let ch = chapter()
        let layout = try ReaderPaginator.paginate(chapter: ch, size: canvas, preferences: ReadingPreferences())
        XCTAssertGreaterThan(layout.pages.count, 2)
        var end = 0
        var restored = ""
        let source = ch.readingText as NSString
        for (index, page) in layout.pages.enumerated() {
            XCTAssertEqual(page.range.location, end)
            XCTAssertGreaterThan(page.range.length, 0)
            let visible = CTFrameGetVisibleStringRange(layout.frames[index])
            XCTAssertEqual(visible.location, page.range.location)
            XCTAssertEqual(visible.length, page.range.length)
            // Page boundaries must also be valid extended grapheme boundaries.
            XCTAssertNotNil(Range(page.range, in: ch.readingText))
            restored += source.substring(with: page.range)
            end = page.endOffset
        }
        XCTAssertEqual(end, ch.readingLength)
        XCTAssertEqual(restored, ch.readingText)
    }

    func testExactPageBoundaryBelongsToNextPage() throws {
        let layout = try ReaderPaginator.paginate(chapter: chapter(), size: canvas, preferences: ReadingPreferences())
        XCTAssertEqual(layout.pageIndex(containing: layout.pages[1].range.location), 1)
        XCTAssertEqual(layout.pageIndex(containing: Int.max), layout.pages.count - 1)
        XCTAssertEqual(layout.pageIndex(containing: -1), 0)
    }

    func testEmptyChapterProducesOneEmptyPage() throws {
        let layout = try ReaderPaginator.paginate(chapter: Chapter(id: "empty", title: "", content: []), size: canvas, preferences: ReadingPreferences())
        XCTAssertEqual(layout.pages.count, 1)
        XCTAssertEqual(layout.pages[0].range.length, 0)
    }

    func testTinyViewportFailsWithoutSkippingText() {
        XCTAssertThrowsError(try ReaderPaginator.paginate(chapter: chapter(), size: CGSize(width: 10, height: 10), preferences: ReadingPreferences()))
    }

    func testPageTurnsChangeTextAndChapterProgress() throws {
        try withStorage { storage, _ in
            let state = makeState(storage: storage)
            let oldText = state.currentPageText
            let oldProgress = try XCTUnwrap(state.activeBook).progressPercentage
            state.nextPage()
            XCTAssertNotEqual(oldText, state.currentPageText)
            XCTAssertGreaterThan(try XCTUnwrap(state.activeBook).progressPercentage, oldProgress)
        }
    }

    func testFontSpacingAndResizePreserveExactAnchorWithoutDrift() throws {
        try withStorage { storage, _ in
            let state = makeState(storage: storage)
            state.nextPage(); state.nextPage()
            let anchor = try XCTUnwrap(state.activeBook?.readingLocation)
            state.updatePreferences { $0.fontSize = 26; $0.lineSpacing = 16 }
            XCTAssertEqual(state.activeBook?.readingLocation, anchor)
            XCTAssertTrue(try XCTUnwrap(state.currentPage).contains(anchor.utf16Offset))
            state.prepareReader(size: CGSize(width: 500, height: 300))
            XCTAssertEqual(state.activeBook?.readingLocation, anchor)
            XCTAssertTrue(try XCTUnwrap(state.currentPage).contains(anchor.utf16Offset))
            state.updatePreferences { $0.fontSize = 17; $0.lineSpacing = 8 }
            state.prepareReader(size: canvas)
            XCTAssertEqual(state.activeBook?.readingLocation, anchor)
            XCTAssertEqual(state.activeBook?.currentPageIndex, 2)
        }
    }

    func testPreviousPageAcrossChapterReturnsToLastPage() throws {
        try withStorage { storage, _ in
            let state = makeState(storage: storage)
            state.jumpToChapter(1)
            state.prevPage()
            XCTAssertEqual(state.activeBook?.currentChapterIndex, 0)
            XCTAssertEqual(state.activeBook?.currentPageIndex, try XCTUnwrap(state.pagination).pages.count - 1)
            state.nextPage()
            XCTAssertEqual(state.activeBook?.currentChapterIndex, 1)
            XCTAssertEqual(state.activeBook?.currentPageIndex, 0)
        }
    }

    func testBookmarkSurvivesReflowAndReturnsToText() throws {
        try withStorage { storage, _ in
            let state = makeState(storage: storage)
            state.nextPage(); state.nextPage()
            let snippet = String(state.currentPageText.prefix(60))
            state.toggleBookmark()
            let bookmark = try XCTUnwrap(state.bookmarks.first)
            XCTAssertEqual(bookmark.snippet, snippet)
            state.updatePreferences { $0.fontSize = 25 }
            state.jumpToChapter(1)
            state.jumpToBookmark(bookmark)
            XCTAssertEqual(state.activeBook?.readingLocation, bookmark.location)
            XCTAssertTrue(state.isCurrentPageBookmarked)
            state.toggleBookmark()
            XCTAssertTrue(state.bookmarks.isEmpty)
        }
    }

    func testRelaunchRestoresTextAnchorAndPreferences() throws {
        try withStorage { storage, _ in
            let state = makeState(storage: storage)
            state.nextPage(); state.nextPage()
            state.updatePreferences { $0.lineSpacing = 12 }
            let anchor = state.activeBook?.readingLocation
            let relaunched = AppState(storage: storage)
            relaunched.openBook(relaunched.books[0])
            relaunched.prepareReader(size: canvas)
            XCTAssertEqual(relaunched.activeBook?.readingLocation, anchor)
            XCTAssertEqual(relaunched.preferences.lineSpacing, 12)
            XCTAssertEqual(relaunched.currentPageText, state.currentPageText)
        }
    }

    func testProgressSeekCanReachBothEndsAndFinalPageIs100Percent() throws {
        try withStorage { storage, _ in
            let state = makeState(storage: storage)
            state.jumpToProgress(1)
            XCTAssertEqual(try XCTUnwrap(state.activeBook).progressPercentage, 100, accuracy: 0.001)
            XCTAssertEqual(state.activeBook?.currentChapterIndex, 1)
            state.jumpToProgress(0)
            XCTAssertEqual(state.activeBook?.currentChapterIndex, 0)
            XCTAssertEqual(state.activeBook?.currentPageIndex, 0)
            let anchor = state.activeBook?.readingLocation
            state.jumpToProgress(.nan)
            XCTAssertEqual(state.activeBook?.readingLocation, anchor)
        }
    }

    func testClearingShelfRemainsEmptyAfterRelaunchAndUndoPreservesOrder() {
        withStorage { storage, _ in
            let state = AppState(storage: storage)
            let originalIDs = state.books.map(\.id)
            state.deleteBook(id: originalIDs[0])
            state.undoDelete()
            XCTAssertEqual(state.books.map(\.id), originalIDs)
            for id in originalIDs { state.deleteBook(id: id) }
            XCTAssertTrue(AppState(storage: storage).books.isEmpty)
        }
    }

    func testRestoringRemovedSampleKeepsItsReadingRecord() throws {
        try withStorage { storage, _ in
            let state = AppState(storage: storage)
            let id = state.books[0].id
            state.openBook(state.books[0])
            state.prepareReader(size: CGSize(width: 220, height: 180))
            state.nextPage()
            let anchor = try XCTUnwrap(state.activeBook?.readingLocation)
            state.deleteBook(id: id)
            state.restoreSampleBooks()
            let restored = try XCTUnwrap(state.books.first { $0.id == id })
            XCTAssertEqual(restored.readingLocation, anchor)
        }
    }

    func testPageTurnsDoNotRewriteCatalog() {
        withStorage { storage, defaults in
            let state = makeState(storage: storage)
            let catalog = defaults.data(forKey: "interline_saved_books_v1")
            state.nextPage(); state.nextPage()
            XCTAssertEqual(defaults.data(forKey: "interline_saved_books_v1"), catalog)
            XCTAssertNotNil(storage.loadRecord(bookID: "test-book")?.location)
        }
    }

    func testLegacyBooksAndBookmarksDecodeWithoutAnchors() throws {
        try withStorage { storage, defaults in
            let book = Book(id: "legacy", title: "旧书", author: "旧作者", currentPageIndex: 1, chapters: [chapter()])
            let json = try JSONEncoder().encode([book])
            var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [[String: Any]])
            objects[0].removeValue(forKey: "readingLocation")
            objects[0].removeValue(forKey: "visibleEndOffset")
            defaults.set(try JSONSerialization.data(withJSONObject: objects), forKey: "interline_saved_books_v1")
            let old = """
            [{"id":"bm","bookId":"legacy","chapterIndex":0,"chapterTitle":"旧章","pageIndex":1,"snippet":"旧摘要","createdAt":0}]
            """
            defaults.set(Data(old.utf8), forKey: "interline_saved_bookmarks_v1")
            let state = AppState(storage: storage)
            state.openBook(state.books[0])
            state.prepareReader(size: canvas)
            XCTAssertEqual(state.activeBook?.currentPageIndex, 1)
            state.jumpToBookmark(try XCTUnwrap(state.bookmarks.first))
            XCTAssertEqual(state.activeBook?.currentPageIndex, 1)
            XCTAssertNotNil(state.activeBook?.readingLocation)
        }
    }

    func testCorruptCatalogIsPreservedAndReported() {
        withStorage { storage, defaults in
            let invalid = Data("invalid-json".utf8)
            defaults.set(invalid, forKey: "interline_saved_books_v1")
            XCTAssertTrue(storage.loadBooks().isEmpty)
            XCTAssertNotNil(storage.lastError)
            XCTAssertEqual(defaults.data(forKey: "interline_saved_books_v1"), invalid)
        }
    }

    func testInvalidLegacyChapterIsRepairedAndSearchTrimsWhitespace() {
        withStorage { storage, _ in
            let book = Book(id: "bad", title: "测试书", author: "作者", currentChapterIndex: -3, chapters: [chapter()])
            storage.saveBooks([book])
            let state = AppState(storage: storage)
            XCTAssertEqual(state.books[0].currentChapterIndex, 0)
            state.searchText = "  测试书  "
            XCTAssertEqual(state.filteredBooks.count, 1)
            state.searchText = "\n "
            XCTAssertEqual(state.filteredBooks.count, 1)
        }
    }
}
