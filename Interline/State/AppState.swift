import SwiftUI
import Combine

// MARK: - Central Application State
// Strict adherence to AGENTS.md Section 5 (Bookshelf & Reader Core Experience)
// and Section 7 (Separate views, models, state, persistence; MainActor concurrency).

@MainActor
public final class AppState: ObservableObject {
    @Published public var books: [Book] = []
    @Published public var activeBookId: String? = nil
    @Published public var preferences: ReadingPreferences = ReadingPreferences()
    @Published public var bookmarks: [Bookmark] = []

    // Reader UI Presentation State
    @Published public var isReaderPresented: Bool = false
    @Published public var areControlsVisible: Bool = false
    @Published public var isTOCPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false

    // Bookshelf State
    @Published public var searchText: String = ""
    @Published public var isEditingBookshelf: Bool = false
    @Published public var toastMessage: String? = nil

    private var deletedBookBackup: Book? = nil
    private var toastDismissTask: Task<Void, Never>? = nil

    private let storage = ReadingStorage.shared

    public init() {
        self.books = storage.loadBooks()
        self.preferences = storage.loadPreferences()
        self.bookmarks = storage.loadBookmarks()
    }

    // MARK: - Computed Properties
    public var activeBook: Book? {
        get {
            guard let id = activeBookId else { return nil }
            return books.first(where: { $0.id == id })
        }
        set {
            guard let newValue = newValue, let index = books.firstIndex(where: { $0.id == newValue.id }) else { return }
            books[index] = newValue
            storage.saveBooks(books)
        }
    }

    public var featuredBook: Book? {
        books.sorted(by: { $0.lastReadDate > $1.lastReadDate }).first
    }

    public var filteredBooks: [Book] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return books
        }
        let query = searchText.lowercased()
        return books.filter { $0.title.lowercased().contains(query) || $0.author.lowercased().contains(query) }
    }

    public var currentBookBookmarks: [Bookmark] {
        guard let activeBook = activeBook else { return [] }
        return bookmarks.filter { $0.bookId == activeBook.id }
    }

    public var isCurrentPageBookmarked: Bool {
        guard let book = activeBook else { return false }
        return bookmarks.contains {
            $0.bookId == book.id && $0.chapterIndex == book.currentChapterIndex && $0.pageIndex == book.currentPageIndex
        }
    }

    // MARK: - Reader Lifecycle Actions
    public func openBook(_ book: Book) {
        self.activeBookId = book.id
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index].lastReadDate = Date()
            storage.saveBooks(books)
        }
        self.areControlsVisible = false
        self.isReaderPresented = true
    }

    public func closeReader() {
        self.isReaderPresented = false
        self.areControlsVisible = false
        self.isTOCPresented = false
        self.isSettingsPresented = false
    }

    public func toggleControls() {
        withAnimation(.easeInOut(duration: 0.22)) {
            areControlsVisible.toggle()
        }
    }

    public func hideControls() {
        if areControlsVisible {
            withAnimation(.easeInOut(duration: 0.22)) {
                areControlsVisible = false
            }
        }
    }

    // MARK: - Page & Chapter Navigation (起点读书 / 微信读书体验)
    public func nextPage() {
        guard var book = activeBook else { return }
        guard let currentChapter = book.currentChapter else { return }
        let totalPagesInChapter = max(1, (currentChapter.content.count + 1) / 2) // Approximation for pagination

        if book.currentPageIndex + 1 < totalPagesInChapter {
            book.currentPageIndex += 1
            self.activeBook = book
        } else if book.currentChapterIndex + 1 < book.chapters.count {
            book.currentChapterIndex += 1
            book.currentPageIndex = 0
            self.activeBook = book
        }
    }

    public func prevPage() {
        guard var book = activeBook else { return }
        if book.currentPageIndex > 0 {
            book.currentPageIndex -= 1
            self.activeBook = book
        } else if book.currentChapterIndex > 0 {
            book.currentChapterIndex -= 1
            let prevChapter = book.chapters[book.currentChapterIndex]
            let prevTotalPages = max(1, (prevChapter.content.count + 1) / 2)
            book.currentPageIndex = max(0, prevTotalPages - 1)
            self.activeBook = book
        }
    }

    public func nextChapter() {
        guard var book = activeBook else { return }
        if book.currentChapterIndex + 1 < book.chapters.count {
            book.currentChapterIndex += 1
            book.currentPageIndex = 0
            self.activeBook = book
        }
    }

    public func prevChapter() {
        guard var book = activeBook else { return }
        if book.currentChapterIndex > 0 {
            book.currentChapterIndex -= 1
            book.currentPageIndex = 0
            self.activeBook = book
        }
    }

    public func jumpToChapter(_ index: Int) {
        guard var book = activeBook else { return }
        guard index >= 0 && index < book.chapters.count else { return }
        book.currentChapterIndex = index
        book.currentPageIndex = 0
        self.activeBook = book
        self.isTOCPresented = false
        self.areControlsVisible = false
    }

    // MARK: - Bookmarks
    public func toggleBookmark() {
        guard let book = activeBook, let currentChapter = book.currentChapter else { return }
        if let existingIndex = bookmarks.firstIndex(where: {
            $0.bookId == book.id && $0.chapterIndex == book.currentChapterIndex && $0.pageIndex == book.currentPageIndex
        }) {
            bookmarks.remove(at: existingIndex)
            storage.saveBookmarks(bookmarks)
            showToast("已移除书签")
        } else {
            let snippet = currentChapter.content.first ?? currentChapter.title
            let newBookmark = Bookmark(
                bookId: book.id,
                chapterIndex: book.currentChapterIndex,
                chapterTitle: currentChapter.title,
                pageIndex: book.currentPageIndex,
                snippet: String(snippet.prefix(60))
            )
            bookmarks.append(newBookmark)
            storage.saveBookmarks(bookmarks)
            showToast("已添加书签")
        }
    }

    // MARK: - Bookshelf Management & Undo
    public func deleteBook(id: String) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        deletedBookBackup = books[index]
        books.remove(at: index)
        storage.saveBooks(books)
        showToast("已从书架移出《\(deletedBookBackup?.title ?? "")》")
    }

    public func undoDelete() {
        guard let backup = deletedBookBackup else { return }
        books.append(backup)
        storage.saveBooks(books)
        deletedBookBackup = nil
        toastMessage = nil
    }

    public func showToast(_ message: String) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                self.toastMessage = nil
            }
        }
    }

    // MARK: - Reading Preferences
    public func updatePreferences(_ modify: (inout ReadingPreferences) -> Void) {
        modify(&preferences)
        storage.savePreferences(preferences)
    }
}
