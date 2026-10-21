import SwiftUI

struct NoteEditorView: View {
    let draft: NoteDraft
    var onSaved: () -> Void = {}
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var errorMessage: String?
    @State private var saved = false

    init(draft: NoteDraft, onSaved: @escaping () -> Void = {}) {
        self.draft = draft; self.onSaved = onSaved
        _note = State(initialValue: draft.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("摘录") { Text(draft.quote).textSelection(.enabled) }
                Section("笔记") {
                    TextEditor(text: $note).frame(minHeight: 160).accessibilityLabel("笔记内容")
                        .accessibilityIdentifier("noteEditor")
                }
                Section { Text("输入自动保留为草稿；取消后可在数据与存储中继续编辑。").font(.caption).foregroundStyle(.secondary) }
            }
            .safeAreaInset(edge: .top) {
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red)
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08)).accessibilityIdentifier("noteSaveError")
                }
            }
            .navigationTitle(draft.annotationID == nil ? "写笔记" : "编辑笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if persistDraft() { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.accessibilityIdentifier("saveNote") }
            }
            .onChange(of: note) { _, _ in _ = persistDraft() }
            .onDisappear { if !saved { _ = persistDraft() } }
            .interactiveDismissDisabled(errorMessage != nil)
        }
    }

    @discardableResult private func persistDraft() -> Bool {
        var value = draft; value.text = note; value.updatedAt = Date()
        let success = appState.saveDraft(value)
        if !success { errorMessage = "草稿保存失败，请保留此页并重试。" }
        return success
    }

    private func save() {
        let success = appState.saveDraftNote(draft, text: note)
        guard success else {
            let retained = persistDraft()
            errorMessage = retained ? "笔记未能保存，输入已保留为草稿，请重试。" : "笔记与草稿均未保存，请保留此页并重试。"
            return
        }
        guard appState.removeDraft(id: draft.id) else { errorMessage = "笔记已保存，草稿暂未清理；可再次保存或稍后清理。"; return }
        saved = true
        dismiss()
        onSaved()
    }
}
