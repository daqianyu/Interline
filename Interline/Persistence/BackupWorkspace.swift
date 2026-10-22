import Foundation

/// Owns exactly one UUID directory. Strong references keep files alive for workers/pickers.
final class BackupWorkspace: Sendable {
    let directory: URL
    init(parent: URL = FileManager.default.temporaryDirectory) throws {
        directory = parent.appendingPathComponent("InterlineBackup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    func bodyURL(_ index: Int) -> URL { directory.appendingPathComponent("body-\(index).json") }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

public struct BackupExport: Identifiable, Sendable {
    let workspace: BackupWorkspace
    public let url: URL
    public var id: String { url.path }
}

public struct PreparedLibraryBackup: Sendable {
    let workspace: BackupWorkspace
    let manifest: BackupManifest
    var metadata: LibraryBackup { manifest.metadata }

    func readBook(_ header: Book) throws -> Book {
        guard let index = manifest.entries.firstIndex(where: { $0.bookID == header.id }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let entry = manifest.entries[index]
        let data = try BoundedBackupInput.read(workspace.bodyURL(index), maximumBytes: entry.byteCount)
        guard data.count == entry.byteCount, BackupContainer.digest(data) == entry.sha256 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var book = header
        book.chapters = try JSONDecoder().decode([Chapter].self, from: data)
        return book
    }
}

enum BackupWorker {
    static func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) { try operation() }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: { task.cancel() }
    }
}
