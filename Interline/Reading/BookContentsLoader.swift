import Foundation

/// Serializes book reads so rapid switching cannot start many full-body decodes
/// simultaneously. A cancelled queued request exits before reading its file.
actor BookContentsLoader {
    func load(bookID: String, storage: ReadingStorage) throws -> [Chapter] {
        try Task.checkCancellation()
        return try storage.readContents(bookID: bookID)
    }
}
