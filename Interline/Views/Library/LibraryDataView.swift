import SwiftUI
import UniformTypeIdentifiers

struct LibraryDataView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var backupExport: BackupExport?
    @State private var errorMessage: String?
    @State private var recovery: [RecoveryFile] = []
    @State private var editingDraft: NoteDraft?
    @State private var deletingBook: Book?
    @State private var preparedBackup: PreparedLibraryBackup?
    @State private var confirmingRestore = false
    @State private var readingBackup = false

    var body: some View {
        NavigationStack {
            Form {
                if appState.isMaintenanceBusy || readingBackup { Section { ProgressView("正在处理资料，请稍候") } }
                Section("备份与恢复") {
                    Button("导出完整备份", systemImage: "square.and.arrow.up") {
                        Task {
                            do { backupExport = try await appState.exportLibraryBackupFile() }
                            catch { errorMessage = "备份未完成：\(error.localizedDescription)" }
                        }
                    }.accessibilityIdentifier("exportLibraryBackup")
                    Button("从备份恢复", systemImage: "arrow.counterclockwise") { importing = true }
                        .accessibilityIdentifier("restoreLibraryBackup")
                    Text("备份包含正文、阅读位置、书签、笔记、草稿及设置。恢复会合并资料；已有书籍保留当前记录，空书库恢复备份设置。备份未加密，包含私人笔记，请妥善保存。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("新备份使用 .interlinebackup 文件，需新版 Interline 恢复；仍可导入旧 JSON 备份。保留的损坏原始文件请从下方单独导出。")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("backupFormatHelp")
                }
                Section("正文修复") {
                    BookImportButton()
                    Text("正文缺失或无法读取时，重新导入同一 TXT 文件可修复；原有位置与笔记会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("已移出书籍 (\(appState.maintenance.removedBooks.count))") {
                    if appState.maintenance.removedBooks.isEmpty { Text("暂无已移出书籍").foregroundStyle(.secondary) }
                    ForEach(appState.maintenance.removedBooks) { book in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                            HStack {
                                Button("恢复到书架") { _ = appState.restoreRemovedBook(id: book.id) }.buttonStyle(.borderless)
                                Spacer()
                                Button("永久删除", role: .destructive) { deletingBook = book }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("待完成的数据清理") {
                    if appState.maintenance.pendingDeletions.isEmpty { Text("没有待清理的数据").foregroundStyle(.secondary) }
                    ForEach(appState.maintenance.pendingDeletions) { task in Text(task.title) }
                    if !appState.maintenance.pendingDeletions.isEmpty {
                        Button("重试全部清理") { appState.retryPendingDeletions() }.accessibilityIdentifier("retryCleanup")
                    }
                }
                Section("笔记草稿 (\(appState.drafts.count))") {
                    ForEach(appState.drafts.sorted { $0.updatedAt > $1.updatedAt }) { draft in
                        Button { editingDraft = draft } label: {
                            VStack(alignment: .leading) { Text(draft.quote).lineLimit(2); Text(draft.text).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        .swipeActions(allowsFullSwipe: false) { Button("丢弃", role: .destructive) { _ = appState.removeDraft(id: draft.id) } }
                    }
                    if appState.drafts.isEmpty { Text("暂无草稿").foregroundStyle(.secondary) }
                }
                Section("保留的原始文件") {
                    ForEach(recovery) { file in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.url.lastPathComponent).font(.caption).lineLimit(2)
                            Text(file.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            ShareLink("导出原始文件", item: file.url)
                        }
                    }
                    if recovery.isEmpty { Text("没有待恢复的原始文件").foregroundStyle(.secondary) }
                    Text("损坏文件无法保证自动重建。可导出保留的原始文件，或从完整备份恢复。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重试中断的数据恢复") { appState.retryInterruptedRestore(); recovery = appState.recoveryFiles() }
                }
            }
            .disabled(appState.isMaintenanceBusy || readingBackup || appState.isImporting)
            .safeAreaInset(edge: .top) {
                if let errorMessage {
                    HStack {
                        Text(errorMessage).font(.callout).foregroundStyle(.red)
                        Spacer()
                        Button { self.errorMessage = nil; if appState.notice?.isError == true { appState.notice = nil } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("关闭数据错误提示")
                    }.padding(.horizontal).background(Color.red.opacity(0.08)).accessibilityIdentifier("storageError")
                }
            }
            .onChange(of: appState.notice?.id) { _, _ in
                if let notice = appState.notice { errorMessage = notice.isError ? notice.message : nil }
            }
            .navigationTitle("数据与存储").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.disabled(appState.isMaintenanceBusy || readingBackup || appState.isImporting) } }
            .interactiveDismissDisabled(appState.isMaintenanceBusy || readingBackup)
            .onAppear { recovery = appState.recoveryFiles() }
            .sheet(item: $editingDraft) { draft in NoteEditorView(draft: draft) }
            .sheet(item: $backupExport) { backup in
                BackupFileExporter(backup: backup) { backupExport = nil }
            }
            .confirmationDialog("永久删除《\(deletingBook?.title ?? "")》及其笔记？", isPresented: Binding(get: { deletingBook != nil }, set: { if !$0 { deletingBook = nil } }), titleVisibility: .visible) {
                Button("永久删除", role: .destructive) { if let book = deletingBook { appState.permanentlyDeleteBook(id: book.id) }; deletingBook = nil }
            }
            .confirmationDialog("合并此备份中的资料？", isPresented: $confirmingRestore, titleVisibility: .visible) {
                Button("合并恢复") {
                    guard let backup = preparedBackup else { return }
                    Task { if !(await appState.restoreLibraryBackup(backup)) { errorMessage = appState.toastMessage }; preparedBackup = nil; recovery = appState.recoveryFiles() }
                }
                Button("取消", role: .cancel) { preparedBackup = nil }
            } message: { Text("已有书籍、笔记和阅读位置优先保留。请在恢复完成前保持应用打开。") }
            .onChange(of: confirmingRestore) { _, presented in if !presented { preparedBackup = nil } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .interlineBackup]) { result in
                switch result {
                case .success(let url):
                    readingBackup = true
                    Task {
                        defer { readingBackup = false }
                        do {
                            preparedBackup = try await BackupWorker.run { try BackupContainer.prepare(url: url) }
                            confirmingRestore = true
                        } catch { errorMessage = "无法读取备份：\(error.localizedDescription)" }
                    }
                case .failure(let error):
                    if (error as NSError).code != CocoaError.Code.userCancelled.rawValue { errorMessage = error.localizedDescription }
                }
            }
        }
    }
}
