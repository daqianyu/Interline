import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public var books: [Book] = []
    @Published public var activeBookId: String?
    @Published public var preferences = ReadingPreferences()
    @Published public var annotations: [ReadingAnnotation] = []
    @Published public var isBookSearchPresented = false
    @Published public var isSelectionPresented = false
    @Published public private(set) var isPaginating = false
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
    private var textScale: CGFloat = 1
    private let storage: ReadingStorage
    private let usesBackgroundLayout: Bool
    private var paginationTask: Task<Void, Never>?
    private var paginationWorker: Task<[PageSlice], Error>?
    private var layoutGeneration = UUID()
    private struct LayoutKey: Hashable {
        let bookID: String
        let chapterID: String
        let width: Int
        let height: Int
        let fontSize: CGFloat
        let spacing: CGFloat
        let family: ReadingFontFamily
    }
    private var rangeCache: [LayoutKey: [PageSlice]] = [:]
    private var cacheOrder: [LayoutKey] = []

    public init(storage: ReadingStorage = .shared, usesBackgroundLayout: Bool = true) {
        self.storage = storage
        self.usesBackgroundLayout = usesBackgroundLayout
        books = storage.loadBooks()
        preferences = storage.loadPreferences()
        bookmarks = storage.loadBookmarks()
        annotations = storage.loadAnnotations()
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
        cancelPagination()
        isBookSearchPresented = false
        isSelectionPresented = false
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
        cancelPagination()
        isBookSearchPresented = false
        isSelectionPresented = false
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
    public func prepareReader(size: CGSize, scale: CGFloat = 1) {
        let size = CGSize(width: floor(size.width), height: floor(size.height))
        guard size.width > 0, size.height > 0 else { return }
        guard size != viewportSize || scale != textScale || pagination == nil else { return }
        viewportSize = size
        textScale = scale
        rebuildPagination()
    }

    private func cancelPagination() {
        paginationTask?.cancel()
        paginationWorker?.cancel()
        layoutGeneration = UUID()
        isPaginating = false
    }

    private func rebuildPagination(goToLastPage: Bool = false) {
        cancelPagination()
        guard let book = activeBook, let chapter = book.currentChapter, viewportSize != .zero else { return }
        var effectivePreferences = self.preferences
        if effectivePreferences.usesDynamicType ?? true {
            effectivePreferences.fontSize *= textScale
            effectivePreferences.lineSpacing *= textScale
        }
        let preferences = effectivePreferences
        let size = viewportSize
        let key = LayoutKey(bookID: book.id, chapterID: chapter.id, width: Int(size.width), height: Int(size.height),
                            fontSize: preferences.fontSize, spacing: preferences.lineSpacing, family: preferences.fontFamily)
        let generation = layoutGeneration
        paginationError = nil
        if let pages = rangeCache[key] {
            installPagination(pages: pages, chapter: chapter, preferences: preferences, size: size, lastPage: goToLastPage)
            return
        }
        if !usesBackgroundLayout {
            do {
                let pages = try ReaderPaginator.pageRanges(chapter: chapter, size: size, preferences: preferences)
                remember(pages, for: key)
                installPagination(pages: pages, chapter: chapter, preferences: preferences, size: size, lastPage: goToLastPage)
            } catch { pagination = nil; paginationError = "当前区域无法容纳正文，请调整窗口或减小字号" }
            return
        }
        pagination = nil
        isPaginating = true
        let worker = Task.detached(priority: .userInitiated) {
            try ReaderPaginator.pageRanges(chapter: chapter, size: size, preferences: preferences)
        }
        paginationWorker = worker
        paginationTask = Task { [weak self] in
            do {
                let pages = try await worker.value
                guard !Task.isCancelled, let self, self.layoutGeneration == generation,
                      self.activeBookId == book.id else { return }
                self.remember(pages, for: key)
                self.installPagination(pages: pages, chapter: chapter, preferences: preferences, size: size, lastPage: goToLastPage)
                self.isPaginating = false
            } catch {
                guard !Task.isCancelled, let self, self.layoutGeneration == generation else { return }
                self.pagination = nil
                self.isPaginating = false
                self.paginationError = "当前区域无法容纳正文，请调整窗口或减小字号"
            }
        }
    }

    private func remember(_ pages: [PageSlice], for key: LayoutKey) {
        rangeCache[key] = pages
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > 6 { rangeCache.removeValue(forKey: cacheOrder.removeFirst()) }
    }

    private func installPagination(pages: [PageSlice], chapter: Chapter, preferences: ReadingPreferences, size: CGSize, lastPage: Bool) {
        guard var book = activeBook, book.currentChapter?.id == chapter.id else { return }
        let layout = ChapterPagination(text: ReaderPaginator.attributedText(chapter: chapter, preferences: preferences), pages: pages, size: size)
        pagination = layout
        let index: Int
        if lastPage {
            index = pages.count - 1
            book.readingLocation = nil
        } else if let anchor = book.readingLocation, anchor.chapterID == chapter.id {
            index = layout.pageIndex(containing: anchor.utf16Offset)
        } else { index = min(max(0, book.currentPageIndex), pages.count - 1) }
        let page = pages[index]
        book.currentPageIndex = index
        if let anchor = book.readingLocation, anchor.chapterID == chapter.id {
            book.readingLocation = ReadingLocation(chapterID: chapter.id,
                utf16Offset: min(max(0, anchor.utf16Offset), max(0, chapter.readingLength - 1)))
        } else {
            book.readingLocation = ReadingLocation(chapterID: chapter.id, utf16Offset: page.range.location)
        }
        book.visibleEndOffset = page.endOffset
        activeBook = book
    }

    func waitForPagination() async { await paginationTask?.value }

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

// MARK: - Library and anchored annotations
extension AppState {
    public var currentBookAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.bookID == activeBookId }.sorted { $0.createdAt > $1.createdAt }
    }

    public func importBook(_ imported: Book) async -> Bool {
        guard !imported.chapters.isEmpty else { showToast("没有可导入的正文"); return false }
        guard !books.contains(where: { $0.id == imported.id && !$0.chapters.isEmpty }) else { showToast("这本书已经在书架中"); return false }
        let repairing = books.contains(where: { $0.id == imported.id })
        do {
            let store = storage
            try await Task.detached(priority: .userInitiated) { try store.stageContents(of: imported, replacing: repairing) }.value
            guard !books.contains(where: { $0.id == imported.id && !$0.chapters.isEmpty }) else { return false }
            var book = imported
            if let record = storage.loadRecord(bookID: book.id), let anchor = record.location,
               let index = book.chapters.firstIndex(where: { $0.id == anchor.chapterID }) {
                book.currentChapterIndex = index
                book.currentPageIndex = record.pageIndex
                book.readingLocation = anchor
                book.visibleEndOffset = record.visibleEndOffset
            }
            var next = books
            if let index = next.firstIndex(where: { $0.id == book.id }) { next[index] = book }
            else { next.append(book) }
            guard storage.saveBooks(next) else { checkSave(false); return false }
            books = next
            showToast("已导入《\(book.title)》")
            return true
        } catch { showToast("正文保存失败：\(error.localizedDescription)"); return false }
    }

    public func updateBookMetadata(id: String, title: String, author: String) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var next = books
        next[index].title = title
        next[index].author = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未知作者" : author
        if storage.saveBooks(next) { books = next; showToast("书籍信息已保存") }
        else { checkSave(false) }
    }

    public func permanentlyDeleteBook(id: String) {
        let next = books.filter { $0.id != id }
        guard storage.saveBooks(next) else { checkSave(false); return }
        books = next
        if activeBookId == id { closeReader(); activeBookId = nil }
        deletedBookBackup = nil
        let remainingBookmarks = bookmarks.filter { $0.bookId != id }
        let remainingNotes = annotations.filter { $0.bookID != id }
        if storage.saveBookmarks(remainingBookmarks) { bookmarks = remainingBookmarks } else { checkSave(false) }
        if storage.saveAnnotations(remainingNotes) { annotations = remainingNotes } else { checkSave(false) }
        rangeCache = rangeCache.filter { $0.key.bookID != id }
        cacheOrder.removeAll { $0.bookID == id }
        if storage.purgeContents(bookID: id) { showToast("书籍与阅读记录已删除") } else { checkSave(false) }
    }

    public func jumpToLocation(bookID: String, location: ReadingLocation) {
        guard let target = books.first(where: { $0.id == bookID }),
              let index = target.chapters.firstIndex(where: { $0.id == location.chapterID }) else { return }
        if !isReaderPresented || activeBookId != bookID { openBook(target) }
        guard var book = activeBook else { return }
        book.currentChapterIndex = index
        book.currentPageIndex = 0
        book.readingLocation = location
        book.visibleEndOffset = nil
        activeBook = book
        isTOCPresented = false
        isBookSearchPresented = false
        rebuildPagination()
    }

    @discardableResult public func addAnnotation(bookID: String, chapterID: String, range: NSRange, note: String = "") -> Bool {
        guard let chapter = books.first(where: { $0.id == bookID })?.chapters.first(where: { $0.id == chapterID }),
              range.location >= 0, range.length > 0, range.location <= chapter.readingLength,
              range.length <= chapter.readingLength - range.location,
              Range(range, in: chapter.readingText) != nil else { return false }
        var next = annotations
        if let index = next.firstIndex(where: { $0.bookID == bookID && $0.chapterID == chapterID && $0.range == range }) {
            if !note.isEmpty { next[index].note = note }
        } else {
            next.append(ReadingAnnotation(bookID: bookID, chapterID: chapterID, range: range,
                quote: (chapter.readingText as NSString).substring(with: range), note: note))
        }
        guard storage.saveAnnotations(next) else { checkSave(false); return false }
        annotations = next
        showToast(note.isEmpty ? "已添加标注" : "笔记已保存")
        return true
    }

    public func updateAnnotation(id: String, note: String) {
        var next = annotations
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].note = note
        if storage.saveAnnotations(next) { annotations = next } else { checkSave(false) }
    }

    public func removeAnnotation(id: String) {
        let next = annotations.filter { $0.id != id }
        if storage.saveAnnotations(next) { annotations = next } else { checkSave(false) }
    }

    public func removeBookmark(id: String) {
        let next = bookmarks.filter { $0.id != id }
        if storage.saveBookmarks(next) { bookmarks = next } else { checkSave(false) }
    }

    public func notesText(for bookID: String) -> String {
        let title = books.first(where: { $0.id == bookID })?.title ?? "阅读笔记"
        let notes = annotations.filter { $0.bookID == bookID }.sorted { $0.createdAt < $1.createdAt }
        return ([title] + notes.map { "摘录：\($0.quote)\n笔记：\($0.note)" }).joined(separator: "\n\n")
    }
}
