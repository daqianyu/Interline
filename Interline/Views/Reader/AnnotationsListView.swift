import SwiftUI

struct AnnotationsListView: View {
    let bookID: String
    @EnvironmentObject private var appState: AppState
    @State private var editing: ReadingAnnotation?
    @State private var exporting = false
    @State private var document = PlainTextDocument(text: "")

    private var notes: [ReadingAnnotation] { appState.annotations.filter { $0.bookID == bookID }.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        Group {
            if notes.isEmpty { ContentUnavailableView("暂无标注或笔记", systemImage: "highlighter", description: Text("长按阅读正文，或使用选字按钮添加。")) }
            else {
                List {
                    Section {
                        Button("导出全部笔记", systemImage: "square.and.arrow.up") {
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
                            Button("删除标注", systemImage: "trash", role: .destructive) { appState.removeAnnotation(id: annotation.id) }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) { appState.removeAnnotation(id: annotation.id) }
                            Button("编辑") { editing = annotation }.tint(.blue)
                        }
                        .accessibilityHint("轻点返回原文，也可使用操作编辑或删除笔记")
                    }
                }
            }
        }
        .sheet(item: $editing) { annotation in AnnotationEditor(annotation: annotation) }
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText, defaultFilename: "阅读笔记.txt") { result in
            if case .failure(let error) = result { appState.showToast(error.localizedDescription) }
        }
    }
}

private struct AnnotationEditor: View {
    let annotation: ReadingAnnotation
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("摘录") { Text(annotation.quote).textSelection(.enabled) }
                Section("笔记") { TextEditor(text: $note).frame(minHeight: 160).accessibilityLabel("笔记内容") }
            }
            .navigationTitle("编辑笔记")
            .onAppear { note = annotation.note }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { appState.updateAnnotation(id: annotation.id, note: note); dismiss() }
                }
            }
        }
    }
}
