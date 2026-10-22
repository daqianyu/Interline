import SwiftUI

struct NoteEditorView: View {
    let draft: NoteDraft
    var onSaved: () -> Void = {}
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var committing = false

    private var saveState: DraftSaveState? { appState.draftSaveState(for: draft.id) }
    private var visibleError: String? {
        errorMessage ?? (saveState == .failed ? "草稿尚未保存，输入仍在此页。请重试，暂勿关闭应用。" : nil)
    }

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
                        .disabled(committing)
                }
                Section {
                    Text("输入会合并保存为草稿。显示“已保存”后可在数据与存储中继续编辑；保存完成前强制退出可能丢失最新输入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(saveState?.rawValue ?? "尚未输入").accessibilityIdentifier("draftSaveStatus")
                        Spacer()
                        if saveState == .saving { ProgressView().accessibilityHidden(true) }
                        if saveState == .failed {
                            Button("重试保存草稿") { Task { await retryDraft() } }
                                .frame(minHeight: 44).disabled(committing).accessibilityIdentifier("retryDraftSave")
                        }
                    }
                    if let visibleError {
                        Text(visibleError).foregroundStyle(.red).accessibilityIdentifier("noteSaveError")
                    }
                }.font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading).background(.background)
            }
            .navigationTitle(draft.annotationID == nil ? "写笔记" : "编辑笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { Task { await cancel() } }.disabled(committing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(committing ? "保存中" : "保存") { Task { await save() } }
                        .disabled(committing).accessibilityIdentifier("saveNote")
                }
            }
            .onChange(of: note) { _, _ in if !saved { _ = queueDraft() } }
            .onDisappear { if !saved { Task { await appState.flushDrafts() } } }
            .interactiveDismissDisabled(committing || visibleError != nil || saveState == .saving)
        }
    }

    @discardableResult private func queueDraft() -> Bool {
        var value = draft; value.text = note; value.updatedAt = Date()
        let success = appState.queueDraft(value)
        if !success { errorMessage = "草稿未能开始保存，请保留此页并稍后重试。" }
        return success
    }

    private func retryDraft() async {
        guard !committing else { return }
        committing = true
        defer { committing = false }
        if queueDraft(), await appState.flushDrafts() { errorMessage = nil }
    }

    private func cancel() async {
        guard !committing else { return }
        committing = true
        defer { committing = false }
        guard queueDraft(), await appState.flushDrafts() else { return }
        dismiss()
    }

    private func save() async {
        guard !committing else { return }
        committing = true
        defer { committing = false }
        guard queueDraft(), await appState.flushDrafts() else { return }
        let success = appState.saveDraftNote(draft, text: note)
        guard success else {
            errorMessage = "笔记未能保存，输入已保留为草稿，请重试。"
            return
        }
        guard appState.removeDraft(id: draft.id) else { errorMessage = "笔记已保存，草稿暂未清理；可再次保存或稍后清理。"; return }
        saved = true
        dismiss()
        onSaved()
    }
}
