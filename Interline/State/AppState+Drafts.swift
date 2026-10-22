import Foundation

public enum DraftSaveState: String, Sendable {
    case saving = "保存中"
    case saved = "已保存"
    case failed = "未保存"
}

extension AppState {
    public func draft(for id: String) -> NoteDraft? {
        pendingDrafts[id]?.value ?? drafts.first { $0.id == id }
    }

    public func draftSaveState(for id: String) -> DraftSaveState? {
        draftSaveStates[id] ?? (drafts.contains { $0.id == id } ? .saved : nil)
    }

    /// Only changes memory. Disk work is coalesced and serialized by flushDrafts.
    @discardableResult public func queueDraft(_ draft: NoteDraft) -> Bool {
        guard !isMaintenanceBusy, !isImporting else {
            showFailure("资料正在处理，请保留输入并稍后重试保存草稿")
            return false
        }
        pendingDrafts[draft.id] = PendingDraft(value: draft)
        draftSaveStates[draft.id] = .saving
        draftDebounceTask?.cancel()
        guard draftSaveTask == nil else { return true }
        draftDebounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
            guard !Task.isCancelled else { return }
            _ = await self?.flushDrafts()
        }
        return true
    }

    /// Await the same writer from every caller. Cancellation of a view task must
    /// not cancel a write already in progress or release the maintenance gate.
    @discardableResult public func flushDrafts() async -> Bool {
        draftDebounceTask?.cancel()
        draftDebounceTask = nil
        if let task = draftSaveTask { return await task.value }
        guard !pendingDrafts.isEmpty else { return true }
        let task = Task { [self] in
            defer { draftSaveTask = nil }
            while !pendingDrafts.isEmpty {
                let batch = pendingDrafts
                for id in batch.keys { draftSaveStates[id] = .saving }
                var next = drafts.filter { batch[$0.id] == nil }
                next += batch.values.map(\.value).filter { !$0.text.isEmpty }
                guard await storage.saveDraftsInBackground(next) else {
                    for id in pendingDrafts.keys { draftSaveStates[id] = .failed }
                    return false
                }
                drafts = next
                for (id, entry) in batch where pendingDrafts[id]?.revision == entry.revision {
                    pendingDrafts.removeValue(forKey: id)
                    draftSaveStates[id] = .saved
                }
            }
            return true
        }
        draftSaveTask = task
        return await task.value
    }

    func requireSettledDrafts() -> Bool {
        guard pendingDrafts.isEmpty, draftSaveTask == nil else {
            showFailure("仍有未保存的草稿，请先在编辑页保存或重试，再进行此操作")
            return false
        }
        return true
    }

    // Retain synchronous APIs for existing callers, but never race a queued write.
    @discardableResult public func saveDraft(_ draft: NoteDraft) -> Bool {
        guard !isMaintenanceBusy, requireSettledDrafts() else { return false }
        var next = drafts.filter { $0.id != draft.id }
        if !draft.text.isEmpty { next.append(draft) }
        guard storage.saveDrafts(next) else { showFailure(storage.lastError ?? "草稿保存失败，请保留编辑页"); return false }
        drafts = next
        draftSaveStates[draft.id] = .saved
        return true
    }

    @discardableResult public func removeDraft(id: String) -> Bool {
        guard !isMaintenanceBusy, requireSettledDrafts() else { return false }
        let next = drafts.filter { $0.id != id }
        guard storage.saveDrafts(next) else { showFailure(storage.lastError ?? "草稿清理失败"); return false }
        drafts = next
        draftSaveStates.removeValue(forKey: id)
        return true
    }
}
