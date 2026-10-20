import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public var books: [Book] = []
    @Published public var activeBookId: String?
    @Published public var preferences = ReadingPreferences()
    @Published public var bookmarks: [Bookmark] = []
    @Published public private(set) var pagination: ChapterPagination?
    @Published public private(set) var paginationError: String?

    @Published public var isReaderPresented = false
    @Published public var areControlsVisible = false
    @Published public var isTOCPresented = false
    @Published public var isSettingsPresented = false
    @Published public var searchText = ""
    @Published public var isSearchPresented = false
    @Published public var isEditingBookshelf = false
    @Published public var toastMessage: String?

    private var deletedBookBackup: (book: Book, index: Int)?
    private var toastDismissTask: Task<Void, Never>?
    private var viewportSize: CGSize = .zero
    private let storage: ReadingStorage

    public init(storage: ReadingStorage = .shared) {
        self.storage = storage
        books = storage.loadBooks()
        preferences = storage.loadPreferences()
        bookmarks = storage.loadBookmarks()
        if let error = storage.lastError { showToast(error) }
    }

    public var activeBook: Book? {
        get { books.first(where: { $0.id == activeBookId }) }
        set {
            guard let book = newValue, let index = books.firstIndex(where: { $0.id == book.id }) else { return }
            books[index] = book
            checkSave(storage.saveRecord(for: book))
        }
    }

    public var featuredBook: Book? { books.max(by: { $0.lastReadDate < $1.lastReadDate }) }

    public var filteredBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return books }
        return books.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
    }

    public var currentBookBookmarks: [Bookmark] {
        bookmarks.filter { $0.bookId == activeBookId }.sorted { $0.createdAt > $1.createdAt }
    }

    public var currentPage: PageSlice? {
        guard let book = activeBook, let pagination, pagination.pages.indices.contains(book.currentPageIndex) else { return nil }
        return pagination.pages[book.currentPageIndex]
    }

    public var currentPageText: String {
        guard let pagination, let page = currentPage else { return "" }
        return (pagination.text.string as NSString).substring(with: page.range)
    }

    private func matchesCurrentPage(_ bookmark: Bookmark) -> Bool {
        guard let book = activeBook, let page = currentPage, bookmark.bookId == book.id else { return false }
        if let location = bookmark.location {
            return location.chapterID == page.chapterID && (page.contains(location.utf16Offset) ||
                (page.range.length == 0 && location.utf16Offset == 0))
        }
        return bookmark.chapterIndex == book.currentChapterIndex && bookmark.pageIndex == book.currentPageIndex
    }

    public var isCurrentPageBookmarked: Bool { bookmarks.contains(where: matchesCurrentPage) }

    public func openBook(_ book: Book) {
        guard books.contains(where: { $0.id == book.id }) else { return }
        activeBookId = book.id
        pagination = nil
        paginationError = nil
        viewportSize = .zero
        if var current = activeBook {
            current.lastReadDate = Date()
            activeBook = current
        }
        areControlsVisible = false
        isTOCPresented = false
        isSettingsPresented = false
        isReaderPresented = true
    }

    public func closeReader() {
        isReaderPresented = false
        areControlsVisible = false
        isTOCPresented = false
        isSettingsPresented = false
        pagination = nil
    }

    public func toggleControls() {
        withAnimation(.easeInOut(duration: 0.22)) { areControlsVisible.toggle() }
    }

    public func hideControls() {
        withAnimation(.easeInOut(duration: 0.22)) { areControlsVisible = false }
    }

    /// The geometry comes from the actual body canvas, excluding chrome/safe areas.
    public func prepareReader(size: CGSize) {
        let size = CGSize(width: floor(size.width), height: floor(size.height))
        guard size.width > 0, size.height > 0 else { return }
        guard size != viewportSize || pagination == nil else { return }
        viewportSize = size
        rebuildPagination()
    }

    private func rebuildPagination(goToLastPage: Bool = false) {
        guard var book = activeBook, let chapter = book.currentChapter, viewportSize != .zero else { return }
        do {
            let layout = try ReaderPaginator.paginate(chapter: chapter, size: viewportSize, preferences: preferences)
            pagination = layout
            paginationError = nil
            let pageIndex: Int
            if goToLastPage {
                pageIndex = layout.pages.count - 1
                book.readingLocation = nil
            } else if let location = book.readingLocation, location.chapterID == chapter.id {
                pageIndex = layout.pageIndex(containing: location.utf16Offset)
            } else {
                // v1 never stored text anchors. Best-effort mapping of its page index.
                pageIndex = min(max(0, book.currentPageIndex), layout.pages.count - 1)
            }
            let page = layout.pages[pageIndex]
            book.currentPageIndex = pageIndex
            // Preserve the exact anchor on reflow, rather than drifting to earlier text
            // after each font/size change. Navigation explicitly installs a new anchor.
            if let anchor = book.readingLocation, anchor.chapterID == chapter.id {
                book.readingLocation = ReadingLocation(chapterID: chapter.id,
                    utf16Offset: min(max(0, anchor.utf16Offset), max(0, chapter.readingLength - 1)))
            } else {
                book.readingLocation = ReadingLocation(chapterID: chapter.id, utf16Offset: page.range.location)
            }
            book.visibleEndOffset = page.endOffset
            activeBook = book
        } catch {
            pagination = nil
            paginationError = "当前区域无法容纳正文，请调整窗口或减小字号"
        }
    }

    private func selectPage(_ index: Int) {
        guard var book = activeBook, let pagination, pagination.pages.indices.contains(index) else { return }
        let page = pagination.pages[index]
        book.currentPageIndex = index
        book.readingLocation = ReadingLocation(chapterID: page.chapterID, utf16Offset: page.range.location)
        book.visibleEndOffset = page.endOffset
        activeBook = book
    }

    public func nextPage() {
        guard let book = activeBook, let pagination else { return }
        if book.currentPageIndex + 1 < pagination.pages.count { selectPage(book.currentPageIndex + 1) }
        else if book.currentChapterIndex + 1 < book.chapters.count { navigateToChapter(book.currentChapterIndex + 1) }
        else { showToast("已读完本书") }
    }

    public func prevPage() {
        guard let book = activeBook, pagination != nil else { return }
        if book.currentPageIndex > 0 { selectPage(book.currentPageIndex - 1) }
        else if book.currentChapterIndex > 0 { navigateToChapter(book.currentChapterIndex - 1, lastPage: true) }
    }

    public func nextChapter() {
        guard let book = activeBook else { return }
        navigateToChapter(book.currentChapterIndex + 1)
    }

    public func prevChapter() {
        guard let book = activeBook else { return }
        navigateToChapter(book.currentChapterIndex - 1)
    }

    private func navigateToChapter(_ index: Int, lastPage: Bool = false) {
        guard var book = activeBook, book.chapters.indices.contains(index) else { return }
        book.currentChapterIndex = index
        book.currentPageIndex = 0
        book.readingLocation = nil
        book.visibleEndOffset = nil
        activeBook = book
        rebuildPagination(goToLastPage: lastPage)
    }

    public func jumpToChapter(_ index: Int) {
        navigateToChapter(index)
        isTOCPresented = false
        areControlsVisible = false
    }

    public func jumpToBookmark(_ bookmark: Bookmark) {
        guard var book = activeBook, bookmark.bookId == book.id else { return }
        let index = bookmark.location.flatMap { location in book.chapters.firstIndex { $0.id == location.chapterID } }
            ?? bookmark.chapterIndex
        guard book.chapters.indices.contains(index) else { showToast("该书签的章节已不存在"); return }
        book.currentChapterIndex = index
        book.currentPageIndex = max(0, bookmark.pageIndex)
        book.readingLocation = bookmark.location
        book.visibleEndOffset = nil
        activeBook = book
        rebuildPagination()
        isTOCPresented = false
        areControlsVisible = false
    }

    /// Maps the entire book's UTF-16 space to one stable location.
    public func jumpToProgress(_ fraction: Double) {
        guard var book = activeBook, fraction.isFinite else { return }
        let total = book.chapters.reduce(0) { $0 + $1.readingLength }
        guard total > 0 else { return }
        var target = min(total - 1, max(0, Int(Double(total) * min(1, max(0, fraction)))))
        for (index, chapter) in book.chapters.enumerated() {
            if target < chapter.readingLength {
                book.currentChapterIndex = index
                book.currentPageIndex = 0
                book.readingLocation = ReadingLocation(chapterID: chapter.id, utf16Offset: target)
                book.visibleEndOffset = nil
                activeBook = book
                rebuildPagination()
                return
            }
            target -= chapter.readingLength
        }
    }

    public func toggleBookmark() {
        guard let book = activeBook, let chapter = book.currentChapter, let page = currentPage else { return }
        if bookmarks.contains(where: matchesCurrentPage) {
            bookmarks.removeAll(where: matchesCurrentPage)
            if storage.saveBookmarks(bookmarks) { showToast("已移除书签") }
            else { checkSave(false) }
        } else {
            bookmarks.append(Bookmark(bookId: book.id, chapterIndex: book.currentChapterIndex,
                chapterTitle: chapter.title, pageIndex: book.currentPageIndex,
                snippet: String(currentPageText.prefix(60)),
                location: ReadingLocation(chapterID: chapter.id, utf16Offset: page.range.location)))
            if storage.saveBookmarks(bookmarks) { showToast("已添加书签") }
            else { checkSave(false) }
        }
    }

    public func deleteBook(id: String) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        deletedBookBackup = (books[index], index)
        let title = books[index].title
        books.remove(at: index)
        if activeBookId == id { closeReader(); activeBookId = nil }
        // Reading records and bookmarks are retained for undo; no content is purged.
        if storage.saveBooks(books) { showToast("已从书架移出《\(title)》") }
        else { checkSave(false) }
    }

    public func undoDelete() {
        guard let backup = deletedBookBackup else { return }
        books.insert(backup.book, at: min(backup.index, books.count))
        checkSave(storage.saveBooks(books))
        deletedBookBackup = nil
        toastDismissTask?.cancel()
        toastMessage = nil
    }

    public func restoreSampleBooks() {
        for book in SampleBooks.defaultLibrary where !books.contains(where: { $0.id == book.id }) {
            books.append(book)
        }
        if storage.saveBooks(books) { books = storage.loadBooks() }
        else { checkSave(false) }
    }

    public func showToast(_ message: String) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    public func updatePreferences(_ modify: (inout ReadingPreferences) -> Void) {
        modify(&preferences)
        preferences.fontSize = min(ReadingPreferences.maxFontSize, max(ReadingPreferences.minFontSize, preferences.fontSize))
        preferences.lineSpacing = min(20, max(0, preferences.lineSpacing))
        checkSave(storage.savePreferences(preferences))
        rebuildPagination()
    }

    private func checkSave(_ success: Bool) {
        if !success { showToast(storage.lastError ?? "阅读数据保存失败") }
    }
}
