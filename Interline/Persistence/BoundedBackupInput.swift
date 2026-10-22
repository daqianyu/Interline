import Foundation

enum BoundedBackupInput {
    static func fileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        return size
    }

    /// Rechecks actual bytes after metadata preflight, including a file that grows.
    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        try Task.checkCancellation()
        guard maximumBytes >= 0, maximumBytes <= ReadingStorage.maximumBackupBytes,
              try fileSize(url) <= maximumBytes else { throw LibraryBackupError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            // Read one byte past the remaining budget to distinguish exact size from overflow.
            let chunk = try handle.read(upToCount: min(64 * 1_024, maximumBytes - data.count + 1)) ?? Data()
            if chunk.isEmpty { return data }
            guard chunk.count <= maximumBytes - data.count else { throw LibraryBackupError.tooLarge }
            data.append(chunk)
        }
    }
}
