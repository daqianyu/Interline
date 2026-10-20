import SwiftUI

struct BookDetailView: View {
    let bookID: String
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var showingSearch = false
    @State private var showingDelete = false
    @State private var exporting = false
    @State private var exportDocument = PlainTextDocument(text: "")

    private var book: Book? { appState.books.first { $0.id == bookID } }

    var body: some View {
        NavigationStack {
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
                        }
                        .padding(.vertical, 8)
                        Button("继续阅读") { dismiss(); appState.openBook(book) }
                            .disabled(book.chapters.isEmpty)
                    }
                    Section("编辑信息") {
                        TextField("书名", text: $title)
                        TextField("作者", text: $author)
                        Button("保存信息") { appState.updateBookMetadata(id: book.id, title: title, author: author) }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Section("内容") {
                        LabeledContent("章节", value: "\(book.chapters.count)")
                        LabeledContent("正文字符", value: "\(book.totalCharacters)")
                        if let encoding = book.sourceEncoding { LabeledContent("导入编码", value: encoding) }
                        Button("搜索本书正文") { showingSearch = true }.disabled(book.chapters.isEmpty)
                        Button("导出 TXT 正文") {
                            exportDocument = PlainTextDocument(text: book.chapters.map(\.readingText).joined(separator: "\n\n"))
                            exporting = true
                        }
                        .disabled(book.chapters.isEmpty)
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
                        Button("从书架移出", role: .destructive) { appState.deleteBook(id: book.id); dismiss() }
                        Button("永久删除正文与阅读记录", role: .destructive) { showingDelete = true }
                    } footer: { Text("移出可撤销并保留阅读记录；永久删除会一并清除正文、书签和笔记。") }
                }
                .navigationTitle("书籍详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .onAppear { title = book.title; author = book.author }
                .onChange(of: appState.isReaderPresented) { _, reading in if reading { dismiss() } }
                .sheet(isPresented: $showingSearch) { BookSearchView(book: book) }
                .confirmationDialog("永久删除《\(book.title)》及其笔记？", isPresented: $showingDelete, titleVisibility: .visible) {
                    Button("永久删除", role: .destructive) { appState.permanentlyDeleteBook(id: book.id); dismiss() }
                } message: { Text("此操作无法撤销。需要保留正文时，请先导出 TXT。") }
                .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .plainText, defaultFilename: book.title + ".txt") { result in
                    if case .failure(let error) = result { appState.showToast(error.localizedDescription) }
                }
            } else { ContentUnavailableView("书籍已移出", systemImage: "book.closed") }
        }
    }
}
