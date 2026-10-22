import SwiftUI
import UniformTypeIdentifiers

struct BookImportButton: View {
    @State private var showingPicker = false
    @State private var source: ImportSource?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            if loading { ProgressView() }
            else { Label("导入 TXT", systemImage: "plus") }
        }
        .disabled(loading)
        .accessibilityIdentifier("importBook")
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.plainText]) { result in
            switch result {
            case .success(let url):
                loading = true
                Task {
                    do { source = try await Task.detached(priority: .userInitiated) { try TXTImportService.read(url: url) }.value }
                    catch { errorMessage = FileOperationFailure.message(for: error, operation: "文件读取") }
                    loading = false
                }
            case .failure(let error):
                errorMessage = FileOperationFailure.message(for: error, operation: "文件选择")
            }
        }
        .sheet(item: $source) { source in ImportPreviewView(source: source) }
        .alert("导入失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("重新选择文件") { errorMessage = nil; showingPicker = true }
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct ImportPreviewView: View {
    let source: ImportSource
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var encoding = TextEncodingChoice.automatic
    @State private var parsed: ParsedTextBook?
    @State private var title = ""
    @State private var author = "未知作者"
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var parsing = true
    @State private var parseGeneration = UUID()

    private var duplicate: Book? {
        guard let parsed else { return nil }
        return appState.books.first {  $0.contentsUnavailable != true && ($0.id == parsed.book.id || $0.contentFingerprint == parsed.book.contentFingerprint) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("文件") {
                    Text(source.fileName)
                    Picker("文本编码", selection: $encoding) {
                        ForEach(TextEncodingChoice.allCases) { value in Text(value.rawValue).tag(value) }
                    }
                    if parsing { ProgressView("识别正文与章节") }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                        if parsed == nil && !parsing { Button("重试识别") { parseGeneration = UUID() } }
                    }
                }
                if let parsed, !parsing {
                    Section("书籍信息") {
                        TextField("书名", text: $title)
                        TextField("作者", text: $author)
                        LabeledContent("识别编码", value: parsed.detectedEncoding)
                        LabeledContent("章节", value: "\(parsed.book.chapters.count)")
                    }
                    Section("章节预览") {
                        ForEach(parsed.book.chapters.prefix(8)) { chapter in Text(chapter.title) }
                        if parsed.book.chapters.count > 8 { Text("其余章节导入后可在目录查看").foregroundStyle(.secondary) }
                        Text(String(parsed.book.chapters.first?.content.first?.prefix(200) ?? ""))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if let duplicate {
                        Section {
                            Text("相同正文已经在书架中，不会重复添加。")
                            Button("阅读《\(duplicate.title)》") {
                                dismiss()
                                appState.openBook(duplicate)
                            }
                        }
                    }
                }
            }
            .navigationTitle("导入预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "保存中" : "导入") {
                        guard var book = parsed?.book else { return }
                        book.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        book.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
                        if book.author.isEmpty { book.author = "未知作者" }
                        busy = true
                        Task {
                            if await appState.importBook(book) { dismiss() }
                            else { errorMessage = "导入未完成，请检查书架或稍后重试" }
                            busy = false
                        }
                    }
                    .disabled(parsed == nil || parsing || busy || duplicate != nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(busy)
            .task(id: encoding.rawValue + parseGeneration.uuidString) {
                parsing = true
                parsed = nil
                errorMessage = nil
                let data = source.data, name = source.fileName, choice = encoding
                let worker = Task.detached(priority: .userInitiated) { try TXTImportService.parse(data: data, fileName: name, encoding: choice) }
                do {
                    let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                    parsed = result
                    if title.isEmpty { title = result.book.title }
                    parsing = false
                } catch is CancellationError { }
                catch { if !Task.isCancelled { errorMessage = error.localizedDescription; parsing = false } }
            }
        }
    }
}
