import Foundation

extension ReadingStorage {
    public nonisolated func readContents(bookID: String) throws -> [Chapter] {
        try Task.checkCancellation()
        let chapters = try JSONDecoder().decode([Chapter].self, from: Data(contentsOf: contentsURL(bookID: bookID)))
        try Task.checkCancellation()
        return chapters
    }

    func readFile<T: Decodable>(_ type: T.Type, name: String, fallback: T) -> T {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        do { return try decoder.decode(type, from: Data(contentsOf: url)) }
        catch { lastError = "本地数据无法读取，原始文件已保留"; return fallback }
    }

    @discardableResult func writeFile<T: Codable>(_ value: T, name: String) -> Bool {
        guard permitWrite() else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try preserveUnreadableFile(at: url) { _ = try self.decoder.decode(T.self, from: $0) }
            try encoder.encode(value).write(to: url, options: .atomic)
            return true
        } catch { lastError = "本地数据保存失败，请重试"; return false }
    }

    public func loadMaintenance() -> LibraryMaintenanceState {
        readFile(LibraryMaintenanceState.self, name: "maintenance-v1.json", fallback: LibraryMaintenanceState())
    }
    @discardableResult public func saveMaintenance(_ value: LibraryMaintenanceState) -> Bool {
        writeFile(value, name: "maintenance-v1.json")
    }
    public func loadDrafts() -> [NoteDraft] { readFile([NoteDraft].self, name: "drafts-v1.json", fallback: []) }
    @discardableResult public func saveDrafts(_ value: [NoteDraft]) -> Bool {
        guard !isWritingDrafts else { lastError = "草稿正在保存，请稍后重试"; return false }
        return writeFile(value, name: "drafts-v1.json")
    }

    public func recoveryFiles() -> [RecoveryFile] {
        let folder = directory.appendingPathComponent("Recovery")
        var urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])) ?? []
        if FileManager.default.fileExists(atPath: journalURL.path) { urls.append(journalURL) }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
            return RecoveryFile(url: url, date: values.contentModificationDate ?? .distantPast, size: values.fileSize ?? 0)
        }.sorted { $0.date > $1.date }
    }

    private struct Checkpoint: Codable {
        struct File: Codable { let name: String; let data: Data? }
        let files: [File]
        let defaults: Data
    }
    private var journalURL: URL { directory.appendingPathComponent("restore-journal-v1.json") }

    /// File snapshots and UserDefaults are journaled before any multi-file mutation.
    /// An interrupted operation rolls back on next launch; immutable staged bodies may
    /// be left unreferenced, but no existing body is replaced by a backup merge.
    func beginTransaction() throws {
        guard !isWritingDrafts else { lastError = "草稿正在保存，请稍后重试"; throw CocoaError(.fileWriteUnknown) }
        guard !transactionActive else { throw CocoaError(.fileWriteUnknown) }
        guard recoverInterruptedRestore() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try ["catalog-v2.json", "annotations-v1.json", "maintenance-v1.json", "drafts-v1.json"].map { name in
            let url = directory.appendingPathComponent(name)
            return Checkpoint.File(name: name, data: FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil)
        }
        let values = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("interline_") }
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try encoder.encode(Checkpoint(files: files, defaults: data)).write(to: journalURL, options: .atomic)
        transactionActive = true
    }
    func commitTransaction() throws { try FileManager.default.removeItem(at: journalURL); transactionActive = false }

    @discardableResult func recoverInterruptedRestore() -> Bool {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return true }
        guard !isWritingDrafts else { lastError = "草稿正在保存，暂不能恢复资料"; return false }
        do {
            let checkpoint = try decoder.decode(Checkpoint.self, from: Data(contentsOf: journalURL))
            let allowed = Set(["catalog-v2.json", "annotations-v1.json", "maintenance-v1.json", "drafts-v1.json"])
            guard checkpoint.files.allSatisfy({ allowed.contains($0.name) }),
                  let values = try PropertyListSerialization.propertyList(from: checkpoint.defaults, format: nil) as? [String: Any],
                  values.keys.allSatisfy({ $0.hasPrefix("interline_") }) else { throw CocoaError(.coderReadCorrupt) }
            for file in checkpoint.files {
                let url = directory.appendingPathComponent(file.name)
                if let data = file.data { try data.write(to: url, options: .atomic) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("interline_") { defaults.removeObject(forKey: key) }
            for (key, value) in values { defaults.set(value, forKey: key) }
            try FileManager.default.removeItem(at: journalURL)
            transactionActive = false
            return true
        } catch { transactionActive = false; lastError = "上次数据操作尚未恢复，请在数据与存储中重试"; return false }
    }

    public nonisolated static let maximumBackupBytes = 256 * 1_024 * 1_024
    public nonisolated static func readBackup(url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { file in
            result = Result {
                let data = try BoundedBackupInput.read(file, maximumBytes: maximumBackupBytes)
                _ = try decodeBackup(data)
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    public nonisolated static func decodeBackup(_ data: Data) throws -> LibraryBackup {
        guard data.count <= maximumBackupBytes else { throw LibraryBackupError.tooLarge }
        let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
        guard backup.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        let all = backup.books + backup.removedBooks
        let ids = try BackupValidation.bookIDs(all)
        try BackupValidation.references(bookIDs: ids, bookmarks: backup.bookmarks,
                                        annotations: backup.annotations, drafts: backup.drafts)
        let notes = Dictionary(grouping: backup.annotations, by: \.bookID)
        let drafts = Dictionary(grouping: backup.drafts, by: \.bookID)
        for book in all {
            try BackupValidation.book(book, annotations: notes[book.id] ?? [], drafts: drafts[book.id] ?? [])
        }
        return backup
    }

    public func buildBackup(books: [Book], maintenance: LibraryMaintenanceState, preferences: ReadingPreferences,
                            bookmarks: [Bookmark], annotations: [ReadingAnnotation], drafts: [NoteDraft]) async throws -> Data {
        let store = self
        let active = books, removed = maintenance.removedBooks
        let task = Task.detached(priority: .userInitiated) {
            try V1BackupWriter.encode(books: active, removedBooks: removed, preferences: preferences,
                                      bookmarks: bookmarks, annotations: annotations, drafts: drafts,
                                      contentsURL: { store.contentsURL(bookID: $0) })
        }
        return try await withTaskCancellationHandler {
            let data = try await task.value
            try Task.checkCancellation()
            return data
        } onCancel: { task.cancel() }
    }
}
