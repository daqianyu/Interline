import SwiftUI

struct AnnotationsListView: View {
    let bookID: String
    @EnvironmentObject private var appState: AppState
    @State private var editing: ReadingAnnotation?
    @State private var exporting = false
    @State private var document = PlainTextDocument(text: "")
    @State private var errorMessage: String?
    @State private var failedDeletion: String?

    private var notes: [ReadingAnnotation] { appState.annotations.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        Group {
            if notes.isEmpty { ContentUnavailableView("暂无标注或笔记", systemImage: "highlighter", description: Text("长按阅读正文，或使用选字按钮添加。")) }
            else {
                List {
                    Section {
                        Button("导出全部笔记", systemImage: "square.and.arrow.up") {
                            errorMessage = nil; failedDeletion = nil
                            document = PlainTextDocument(text: appState.notesText(for: bookID))
                            exporting = true
                        }
                    }
                    ForEach(notes) { annotation in
                        Button {
                            appState.jumpToLocation(bookID: bookID, location: annotation.location)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(annotation.quote).lineLimit(4)
                                if !annotation.note.isEmpty { Text(annotation.note).foregroundStyle(.secondary) }
                                Text(annotation.createdAt, style: .date).font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .contextMenu {
                            Button("编辑笔记", systemImage: "pencil") { editing = annotation }
                            Button("删除标注", systemImage: "trash", role: .destructive) { remove(annotation.id) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) { remove(annotation.id) }
                            Button("编辑") { editing = annotation }.tint(.blue)
                        }
                        .accessibilityHint("轻点返回原文，也可使用操作编辑或删除笔记")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let errorMessage {
                OperationErrorBanner(message: errorMessage, retry: {
                    if let failedDeletion { remove(failedDeletion) }
                    else { self.errorMessage = nil; document = PlainTextDocument(text: appState.notesText(for: bookID)); exporting = true }
                }, close: { self.errorMessage = nil; failedDeletion = nil })
            }
        }
        .sheet(item: $editing) { annotation in
            let value = NoteDraft(bookID: annotation.bookID, chapterID: annotation.chapterID, range: annotation.range,
                                  quote: annotation.quote, annotationID: annotation.id, text: annotation.note)
            NoteEditorView(draft: appState.draft(for: value.id) ?? value)
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText, defaultFilename: "阅读笔记.txt") { result in
            switch result {
            case .success: errorMessage = nil
            case .failure(let error):
                if let message = FileOperationFailure.message(for: error, operation: "笔记导出") { errorMessage = message; failedDeletion = nil }
            }
        }
    }

    private func remove(_ id: String) {
        errorMessage = appState.removeAnnotation(id: id).errorMessage
        failedDeletion = errorMessage == nil ? nil : id
    }
}
