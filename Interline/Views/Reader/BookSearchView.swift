import SwiftUI

struct BookSearchView: View {
    let book: Book
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [BookSearchMatch] = []
    @State private var searching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("搜索本书正文", systemImage: "doc.text.magnifyingglass", description: Text("输入文字，点击结果返回对应原文。"))
                } else if searching { ProgressView("正在搜索") }
                else if let errorMessage { ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle") }
                else if results.isEmpty { ContentUnavailableView.search(text: query) }
                else {
                    List {
                        Section(results.count == BookSearchService.resultLimit ? "前 200 条结果，请缩小关键词范围" : "\(results.count) 条结果") {
                            ForEach(results) { match in
                                Button {
                                    dismiss()
                                    appState.jumpToLocation(bookID: book.id, location: match.location)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(match.chapterTitle).font(.headline)
                                        Text(match.snippet).font(.body).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .accessibilityIdentifier("searchMatch")
                            }
                        }
                    }
                }
            }
            .navigationTitle("搜索正文")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索本书正文")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .task(id: query) {
                results = []
                errorMessage = nil
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searching = false; return }
                searching = true
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    let query = query, book = book
                    let worker = Task.detached(priority: .userInitiated) { try BookSearchService.search(book: book, query: query) }
                    let matches = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                    results = matches
                    searching = false
                } catch is CancellationError { }
                catch { if !Task.isCancelled { errorMessage = error.localizedDescription; searching = false } }
            }
        }
    }
}
