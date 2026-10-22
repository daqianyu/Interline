import SwiftUI

struct BookDetailView: View {
    let bookID: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var initialized = false
    @State private var showingSearch = false
    @State private var showingDelete = false
    @State private var exporting = false
    @State private var loadedBook: Book?
    @State private var loadError: String?
    @State private var loadGeneration = UUID()
    @State private var preparingExport = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportDocument = PlainTextDocument(text: "")
    @State private var errorMessage: String?
    @State private var failedAction: Action?
    private enum Action: Equatable { case metadata, removal, permanentDeletion, export }

    private var book: Book? {
        guard var value = appState.books.first(where: { $0.id == bookID }) else { return nil }
        if let loadedBook { value.chapters = loadedBook.chapters }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    OperationErrorBanner(message: errorMessage, retry: { if let failedAction { perform(failedAction) } }, close: { self.errorMessage = nil; failedAction = nil })
                }
                Group {
                    if let book {
                        Form {
                            Section {
                                HStack(spacing: 20) {
                                    BookCoverView(book: book, width: 72, height: 100).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(book.title).font(.title3.bold())
                                        Text(book.author).foregroundStyle(.secondary)
                                        Text(String(format: "阅读进度 %.1f%%", book.progressPercentage)).font(.callout)
                                    }
                                }.padding(.vertical, 8)
                                Button("继续阅读") { dismiss(); appState.openBook(book) }.disabled(book.contentsUnavailable == true)
                            }
                            Section("编辑信息") {
                                TextField("书名", text: $title).accessibilityIdentifier("detailTitle")
                                TextField("作者", text: $author)
                                Button("保存信息") { perform(.metadata) }
                                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityIdentifier("saveBookMetadata")
                            }
                            Section("内容") {
                                LabeledContent("章节", value: "\(book.summaries.count)")
                                if loadedBook == nil && loadError == nil { ProgressView("正在加载正文") }
                                if let loadError {
                                    Text(loadError).foregroundStyle(.red)
                                    Button("重试读取正文") { self.loadError = nil; loadGeneration = UUID() }
                                    BookImportButton()
                                }
                                LabeledContent("正文字符", value: "\(book.totalCharacters)")
                                if let encoding = book.sourceEncoding { LabeledContent("导入编码", value: encoding) }
                                Button("搜索本书正文") { showingSearch = true }.disabled(book.chapters.isEmpty)
                                Button("导出 TXT 正文") { prepareExport() }
                                    .disabled(book.chapters.isEmpty || preparingExport)
                                    .accessibilityIdentifier("exportBookText")
                                if preparingExport { ProgressView("正在准备正文") }
                            }
                            Section("目录") {
                                ForEach(book.chapters) { chapter in
                                    Button(chapter.title) {
                                        dismiss()
                                        appState.jumpToLocation(bookID: book.id, location: ReadingLocation(chapterID: chapter.id, utf16Offset: 0))
                                    }
                                }
                            }
                            Section {
                                Button("从书架移出", role: .destructive) { perform(.removal) }.accessibilityIdentifier("removeBookFromDetail")
                                Button("永久删除正文与阅读记录", role: .destructive) { showingDelete = true }
                            } footer: { Text("移出可撤销并保留阅读记录；永久删除会一并清除正文、书签和笔记。") }
                        }
                        .onAppear {
                            if !initialized { title = book.title; author = book.author; initialized = true }
                        }
                        .sheet(isPresented: $showingSearch) { BookSearchView(book: book) }
                    } else {
                        ContentUnavailableView("书籍已移出", systemImage: "book.closed", description: Text("若数据清理未完成，可在此重试或到数据与存储继续处理。"))
                    }
                }
                .disabled(appState.isMaintenanceBusy || appState.isImporting)
            }
            .navigationTitle("书籍详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: loadGeneration) {
                guard let book else { return }
                do {
                    let loaded = try await appState.details(for: book)
                    try Task.checkCancellation()
                    loadedBook = loaded; loadError = nil
                } catch is CancellationError { }
                catch { if !Task.isCancelled { loadError = "正文无法读取，请重试或重新导入同一 TXT 文件修复。" } }
            }
            .onDisappear { exportTask?.cancel() }
            .onChange(of: appState.isReaderPresented) { _, reading in if reading { dismiss() } }
            .confirmationDialog("永久删除《\(book?.title ?? title)》及其笔记？", isPresented: $showingDelete, titleVisibility: .visible) {
                Button("永久删除", role: .destructive) { perform(.permanentDeletion) }
            } message: { Text("此操作无法撤销。需要保留正文时，请先导出 TXT。") }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .plainText, defaultFilename: (book?.title ?? title) + ".txt") { result in
                switch result {
                case .success: errorMessage = nil; failedAction = nil
                case .failure(let error):
                    if let message = FileOperationFailure.message(for: error, operation: "正文导出") { errorMessage = message; failedAction = .export }
                }
            }
        }
    }

    private func perform(_ action: Action) {
        if action == .export { prepareExport(); return }
        let result: LibraryActionResult
        switch action {
        case .metadata: result = appState.updateBookMetadata(id: bookID, title: title, author: author)
        case .removal: result = appState.deleteBook(id: bookID)
        case .permanentDeletion: result = appState.permanentlyDeleteBook(id: bookID)
        case .export: return
        }
        errorMessage = result.errorMessage
        failedAction = errorMessage == nil ? nil : action
        if result == .success, action != .metadata { dismiss() }
    }

    private func prepareExport() {
        guard !preparingExport, let chapters = book?.chapters, !chapters.isEmpty else { return }
        preparingExport = true
        errorMessage = nil
        exportTask = Task {
            defer { preparingExport = false; exportTask = nil }
            do {
                let text = try await BackupWorker.run {
                    try chapters.map { chapter in try Task.checkCancellation(); return chapter.readingText }.joined(separator: "\n\n")
                }
                try Task.checkCancellation()
                exportDocument = PlainTextDocument(text: text)
                failedAction = nil; exporting = true
            } catch {
                if let message = FileOperationFailure.message(for: error, operation: "正文导出") { errorMessage = message; failedAction = .export }
            }
        }
    }
}
