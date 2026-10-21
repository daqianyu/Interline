import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    @Published public var books: [Book] = []
    @Published public var activeBookId: String?
    @Published public var preferences = ReadingPreferences()
    @Published public var annotations: [ReadingAnnotation] = []
    @Published public var isBookSearchPresented = false
    @Published public var selectionSnapshot: ReadingSelectionSnapshot?
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
    @Published public var notice: AppNotice?
    public var toastMessage: String? { notice?.message }
    @Published public internal(set) var maintenance = LibraryMaintenanceState()
    @Published public internal(set) var drafts: [NoteDraft] = []
    @Published public internal(set) var isMaintenanceBusy = false
    @Published public private(set) var isLoadingBook = false
    @Published public private(set) var isImporting = false
    @Published public var isStoragePresented = false
    @Published public var shelfSort = ShelfSort.recentlyRead
    @Published public var shelfFilter = ShelfFilter.all
    @Published public private(set) var navigationHistory: [ReadingLocation] = []
    @Published public private(set) var searchHighlight: ReadingHighlight?
    private var highlightTask: Task<Void, Never>?
    private var bookLoadTask: Task<Void, Never>?
    private var bookLoadGeneration = UUID()
    let loadsContentsOnDemand: Bool
    private var pendingLocation: ReadingLocation?
    private var pendingHighlight: ReadingHighlight?

    var deletedBookBackup: (book: Book, index: Int)?
    private var toastDismissTask: Task<Void, Never>?
    private var viewportSize: CGSize = .zero
    private var textScale: CGFloat = 1
    let storage: ReadingStorage
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
        let paragraphSpacing: CGFloat
        let family: ReadingFontFamily
    }
    private var rangeCache: [LayoutKey: [PageSlice]] = [:]
    private var cacheOrder: [LayoutKey] = []

    public init(storage: ReadingStorage = .shared, usesBackgroundLayout: Bool = true, loadsContentsOnDemand: Bool = false) {
        self.storage = storage
        self.usesBackgroundLayout = usesBackgroundLayout
        self.loadsContentsOnDemand = loadsContentsOnDemand
        books = storage.loadBooks(includeContents: !loadsContentsOnDemand)
        preferences = storage.loadPreferences()
        bookmarks = storage.loadBookmarks()
        annotations = storage.loadAnnotations()
        maintenance = storage.loadMaintenance()
        drafts = storage.loadDrafts()
        if let error = storage.lastError { showFailure(error) }
        if loadsContentsOnDemand { Task { [weak self] in await self?.indexMissingSummaries() } }
    }

    public var activeBook: Book? {
        get { books.first(where: { $0.id == activeBookId }) }
        set {
            guard let book = newValue, let index = books.firstIndex(where: { $0.id == book.id }) else { return }
            books[index] = book
            checkSave(storage.saveRecord(for: book))
        }
    }

    public var canUndoDelete: Bool { deletedBookBackup != nil }

    public var featuredBook: Book? { books.max(by: { $0.lastReadDate < $1.lastReadDate }) }

    public var filteredBooks: [Book] {
        LibraryPolicy.filtered(books, query: searchText, filter: shelfFilter, sort: shelfSort)
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
        guard !isMaintenanceBusy, let saved = books.first(where: { $0.id == book.id }) else { return }
        guard saved.contentsUnavailable != true else {
            showFailure("正文暂不可用，请在数据与存储中重新导入同一 TXT 文件")
            return
        }
        cancelPagination()
        bookLoadTask?.cancel()
        bookLoadGeneration = UUID()
        isBookSearchPresented = false
        selectionSnapshot = nil
        navigationHistory = []
        clearSearchHighlight()
        activeBookId = book.id
        if loadsContentsOnDemand { books = books.map { $0.id == book.id ? $0 : $0.metadata } }
        pagination = nil
        paginationError = nil
        viewportSize = .zero
        areControlsVisible = false
        isTOCPresented = false
        isSettingsPresented = false
        isReaderPresented = true
        if !saved.chapters.isEmpty { finishOpening(saved); return }
        if !loadsContentsOnDemand {
            do { var loaded = saved; loaded.chapters = try storage.readContents(bookID: book.id); finishOpening(loaded) }
            catch { failOpening(bookID: book.id) }
            return
        }
        isLoadingBook = true
        let generation = bookLoadGeneration, store = storage
        bookLoadTask = Task { [weak self] in
            do {
                let chapters = try await Task.detached(priority: .userInitiated) { try store.readContents(bookID: book.id) }.value
                guard !Task.isCancelled, let self, self.bookLoadGeneration == generation,
                      self.isReaderPresented, self.activeBookId == book.id else { return }
                var loaded = self.activeBook ?? saved
                loaded.chapters = chapters
                self.finishOpening(loaded)
            } catch {
                guard !Task.isCancelled, let self, self.bookLoadGeneration == generation else { return }
                self.failOpening(bookID: book.id)
            }
        }
    }

    private func finishOpening(_ value: Book) {
        guard !value.chapters.isEmpty else { failOpening(bookID: value.id); return }
        var book = value
        book.updateChapterSummaries()
        book.contentsUnavailable = false
        if let anchor = book.readingLocation, let index = book.chapters.firstIndex(where: { $0.id == anchor.chapterID }) {
            book.currentChapterIndex = index
        }
        if !book.chapters.indices.contains(book.currentChapterIndex) {
            book.currentChapterIndex = 0; book.currentPageIndex = 0; book.readingLocation = nil
        }
        if let location = pendingLocation, let index = book.chapters.firstIndex(where: { $0.id == location.chapterID }) {
            book.currentChapterIndex = index; book.currentPageIndex = 0
            book.readingLocation = location; book.visibleEndOffset = nil
        }
        pendingLocation = nil
        book.lastReadDate = Date()
        activeBook = book
        isLoadingBook = false
        rebuildPagination()
        if let highlight = pendingHighlight { pendingHighlight = nil; setSearchHighlight(highlight) }
    }

    private func failOpening(bookID: String) {
        isLoadingBook = false
        if let index = books.firstIndex(where: { $0.id == bookID }) { books[index].contentsUnavailable = true }
        paginationError = "正文暂不可用，请重新导入同一 TXT 文件修复"
        showFailure(paginationError!)
    }

    public func closeReader() {
        cancelPagination()
        bookLoadTask?.cancel(); bookLoadGeneration = UUID(); isLoadingBook = false
        pendingLocation = nil; pendingHighlight = nil
        isBookSearchPresented = false
        selectionSnapshot = nil
        isReaderPresented = false
        areControlsVisible = false
        isTOCPresented = false
        isSettingsPresented = false
        pagination = nil
        navigationHistory = []
        clearSearchHighlight()
        if loadsContentsOnDemand { books = books.map(\.metadata) }
    }

    func waitForBookLoad() async { await bookLoadTask?.value }

    public func handleMemoryWarning() {
        rangeCache.removeAll(); cacheOrder.removeAll()
        if loadsContentsOnDemand {
            books = books.map { $0.id == activeBookId && isReaderPresented ? $0 : $0.metadata }
        }
    }

    private func indexMissingSummaries() async {
        let candidates = books.filter { $0.chapterSummaries == nil }
        let store = storage
        for book in candidates {
            guard !Task.isCancelled else { return }
            let summaries = try? await Task.detached(priority: .utility) { try store.readContents(bookID: book.id).map(ChapterSummary.init) }.value
            if let summaries, let index = books.firstIndex(where: { $0.id == book.id }) { books[index].chapterSummaries = summaries }
        }
        if !candidates.isEmpty, !isMaintenanceBusy { checkSave(storage.saveBooks(books)) }
    }

    public func presentTextSelection() {
        guard let book = activeBook, let page = currentPage else { return }
        selectionSnapshot = ReadingSelectionSnapshot(bookID: book.id, page: page,
            text: currentPageText, preferences: preferences)
        areControlsVisible = false
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
                            fontSize: preferences.fontSize, spacing: preferences.lineSpacing, paragraphSpacing: preferences.paragraphSpacing ?? 0.5, family: preferences.fontFamily)
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
        var renderingPreferences = preferences
        renderingPreferences.theme = self.preferences.theme
        let layout = ChapterPagination(text: ReaderPaginator.attributedText(chapter: chapter, preferences: renderingPreferences), pages: pages, size: size)
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
        rememberCurrentLocation()
        navigateToChapter(index)
        isTOCPresented = false
        areControlsVisible = false
    }

    public func jumpToBookmark(_ bookmark: Bookmark) {
        rememberCurrentLocation()
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
        rememberCurrentLocation()
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
        guard !isMaintenanceBusy, !isImporting else { return }
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let book = books[index]
        var next = books
        next.remove(at: index)
        var nextMaintenance = maintenance
        nextMaintenance.removedBooks.removeAll { $0.id == id }
        nextMaintenance.removedBooks.append(book.metadata)
        do {
            try storage.beginTransaction()
            guard storage.saveMaintenance(nextMaintenance), storage.saveBooks(next) else { throw CocoaError(.fileWriteUnknown) }
            try storage.commitTransaction()
        } catch { _ = storage.recoverInterruptedRestore(); showFailure(storage.lastError ?? "移出失败，请重试"); return }
        deletedBookBackup = (book, index)
        maintenance = nextMaintenance
        books = next
        if activeBookId == id { closeReader(); activeBookId = nil }
        // Reading records and bookmarks are retained for undo; no content is purged.
        showToast("已从书架移出《\(book.title)》", action: .undoRemoval)
    }

    public func undoDelete() {
        guard let backup = deletedBookBackup else { return }
        if restoreRemovedBook(id: backup.book.id) { deletedBookBackup = nil; notice = nil }
    }

    public func restoreSampleBooks() {
        var next = books
        for book in SampleBooks.defaultLibrary where !next.contains(where: { $0.id == book.id }) {
            next.append(book)
        }
        if storage.saveBooks(next) { books = storage.loadBooks(includeContents: !loadsContentsOnDemand) }
        else { checkSave(false) }
    }

    public func showToast(_ message: String, action: NoticeAction? = nil) {
        toastDismissTask?.cancel()
        let value = AppNotice(message: message, isError: false, action: action)
        notice = value
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(action == nil ? 3 : 8))
            guard !Task.isCancelled, self?.notice?.id == value.id else { return }
            self?.notice = nil
        }
    }

    public func showFailure(_ message: String, action: NoticeAction? = nil) {
        toastDismissTask?.cancel()
        notice = AppNotice(message: message, isError: true, action: action)
    }

    public func updatePreferences(_ modify: (inout ReadingPreferences) -> Void) {
        let old = preferences
        var next = old
        modify(&next)
        next.fontSize = min(ReadingPreferences.maxFontSize, max(ReadingPreferences.minFontSize, next.fontSize))
        next.lineSpacing = min(20, max(0, next.lineSpacing))
        next.horizontalMargin = min(48, max(12, next.horizontalMargin ?? 24))
        next.paragraphSpacing = min(1.5, max(0, next.paragraphSpacing ?? 0.5))
        guard storage.savePreferences(next) else { checkSave(false); return }
        preferences = next
        let needsLayout = old.fontSize != next.fontSize || old.lineSpacing != next.lineSpacing || old.fontFamily != next.fontFamily ||
            old.usesDynamicType != next.usesDynamicType || old.paragraphSpacing != next.paragraphSpacing
        if needsLayout { rebuildPagination() }
        else if old.theme != next.theme, let layout = pagination, let chapter = activeBook?.currentChapter {
            var effective = next
            if effective.usesDynamicType ?? true { effective.fontSize *= textScale; effective.lineSpacing *= textScale }
            pagination = ChapterPagination(text: ReaderPaginator.attributedText(chapter: chapter, preferences: effective), pages: layout.pages, size: layout.size)
        }
    }

    private func checkSave(_ success: Bool) {
        if !success { showFailure(storage.lastError ?? "阅读数据保存失败") }
    }

}

// MARK: - Library and anchored annotations
extension AppState {
    public var currentBookAnnotations: [ReadingAnnotation] {
        annotations.filter { $0.bookID == activeBookId }.sorted { $0.createdAt > $1.createdAt }
    }

    public func importBook(_ imported: Book) async -> Bool {
        guard !isMaintenanceBusy, !isImporting else { return false }
        guard !maintenance.pendingDeletions.contains(where: { $0.id == imported.id }) else { showFailure("请先在数据与存储中完成此书的数据清理"); return false }
        if maintenance.removedBooks.contains(where: { $0.id == imported.id }) { return restoreRemovedBook(id: imported.id) }
        guard !imported.chapters.isEmpty else { showToast("没有可导入的正文"); return false }
        guard !books.contains(where: { $0.id == imported.id && $0.contentsUnavailable != true }) else { showToast("这本书已经在书架中"); return false }
        let repairing = books.contains(where: { $0.id == imported.id })
        isImporting = true
        defer { isImporting = false }
        do {
            let store = storage
            try await Task.detached(priority: .userInitiated) { try store.stageContents(of: imported, replacing: repairing) }.value
            guard !books.contains(where: { $0.id == imported.id && $0.contentsUnavailable != true }) else { return false }
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
            books = loadsContentsOnDemand ? next.map { $0.id == activeBookId && isReaderPresented ? $0 : $0.metadata } : next
            showToast("已导入《\(book.title)》")
            return true
        } catch { showFailure("正文保存失败：\(error.localizedDescription)"); return false }
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
        guard !isMaintenanceBusy, !isImporting else { return }
        guard let book = books.first(where: { $0.id == id }) ?? maintenance.removedBooks.first(where: { $0.id == id }) else { return }
        var next = maintenance
        next.removedBooks.removeAll { $0.id == id }
        if !next.pendingDeletions.contains(where: { $0.id == id }) { next.pendingDeletions.append(PendingDeletion(id: id, title: book.title, createdAt: Date())) }
        let active = books.filter { $0.id != id }
        do {
            try storage.beginTransaction()
            guard storage.saveMaintenance(next), storage.saveBooks(active) else { throw CocoaError(.fileWriteUnknown) }
            try storage.commitTransaction()
        } catch { _ = storage.recoverInterruptedRestore(); showFailure(storage.lastError ?? "删除失败，请重试"); return }
        maintenance = next; books = active; deletedBookBackup = nil
        if activeBookId == id { closeReader(); activeBookId = nil }
        rangeCache = rangeCache.filter { $0.key.bookID != id }; cacheOrder.removeAll { $0.bookID == id }
        retryPendingDeletions()
    }

    public func jumpToLocation(bookID: String, location: ReadingLocation, highlight: NSRange? = nil, remember: Bool = true) {
        guard let target = books.first(where: { $0.id == bookID }),
              target.summaries.contains(where: { $0.id == location.chapterID }) || !isReaderPresented else { return }
        let previous = activeBook?.readingLocation
        let match = highlight.map { ReadingHighlight(bookID: bookID, chapterID: location.chapterID, range: $0) }
        if !isReaderPresented || activeBookId != bookID {
            pendingLocation = location; pendingHighlight = match
            openBook(target)
            return
        }
        guard var book = activeBook, let index = book.chapters.firstIndex(where: { $0.id == location.chapterID }) else { return }
        if remember, let previous, previous != location { navigationHistory.append(previous); if navigationHistory.count > 20 { navigationHistory.removeFirst() } }
        book.currentChapterIndex = index; book.currentPageIndex = 0; book.readingLocation = location; book.visibleEndOffset = nil
        activeBook = book
        isTOCPresented = false; isBookSearchPresented = false
        if let match { setSearchHighlight(match) } else { clearSearchHighlight() }
        rebuildPagination()
    }

    private func rememberCurrentLocation() {
        if let location = activeBook?.readingLocation {
            navigationHistory.append(location)
            if navigationHistory.count > 20 { navigationHistory.removeFirst() }
        }
    }
    public func persistSession() {
        guard !isLoadingBook, !isMaintenanceBusy, let book = activeBook, !book.chapters.isEmpty else { return }
        checkSave(storage.saveRecord(for: book))
    }
    public func returnToPreviousLocation() {
        guard let id = activeBookId, let location = navigationHistory.popLast() else { return }
        jumpToLocation(bookID: id, location: location, remember: false)
    }
    private func setSearchHighlight(_ highlight: ReadingHighlight) {
        highlightTask?.cancel(); searchHighlight = highlight
        highlightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.searchHighlight = nil
        }
    }
    private func clearSearchHighlight() { highlightTask?.cancel(); searchHighlight = nil }

    @discardableResult public func addAnnotation(bookID: String, chapterID: String, range: NSRange, note: String = "") -> Bool {
        guard let chapter = annotationChapter(bookID: bookID, chapterID: chapterID),
              range.location >= 0, range.length > 0, range.location <= chapter.readingLength,
              range.length <= chapter.readingLength - range.location,
              Range(range, in: chapter.readingText) != nil else { return false }
        let source = chapter.readingText as NSString
        guard source.rangeOfComposedCharacterSequences(for: range) == range else { return false }
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

    @discardableResult public func updateAnnotation(id: String, note: String) -> Bool {
        var next = annotations
        guard let index = next.firstIndex(where: { $0.id == id }) else { showFailure("笔记已不存在，草稿仍会保留"); return false }
        next[index].note = note
        guard storage.saveAnnotations(next) else { checkSave(false); return false }
        annotations = next
        return true
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
