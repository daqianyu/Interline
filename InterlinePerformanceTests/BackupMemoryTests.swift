import XCTest
@testable import Interline

final class BackupMemoryTests: XCTestCase {
    private struct Sample {
        let workspace: BackupWorkspace
        let books: [Book]
        init() throws {
            workspace = try BackupWorkspace()
            var values: [Book] = []
            for index in 0..<20 {
                try autoreleasepool {
                    let chapters = (0..<4).map { chapter in
                        Chapter(id: "chapter-\(chapter)", title: "第\(chapter)章",
                                content: [String(repeating: "文", count: 128 * 1_024) + "书\(index)"])
                    }
                    let book = Book(id: "book-\(index)", title: "测量书籍\(index)", author: "测试样本", chapters: chapters)
                    try JSONEncoder().encode(chapters).write(to: workspace.bodyURL(index), options: .atomic)
                    values.append(book.metadata)
                }
            }
            books = values
        }
        func url(_ id: String) -> URL { workspace.bodyURL(Int(id.dropFirst(5))!) }
    }

    private func record(_ operation: () throws -> Int) {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()], options: options) {
            do { try autoreleasepool { XCTAssertGreaterThan(try operation(), 0) } }
            catch { XCTFail("Backup benchmark failed: \(error)") }
        }
    }

    func testLegacyFullLibrary() throws {
        let sample = try Sample()
        record {
            let hydrated = try sample.books.map { header in
                var book = header
                book.chapters = try JSONDecoder().decode([Chapter].self, from: Data(contentsOf: sample.url(book.id)))
                return book
            }
            let archive = LibraryBackup(version: 1, createdAt: Date(), books: hydrated, removedBooks: [],
                preferences: ReadingPreferences(), bookmarks: [], annotations: [], drafts: [])
            let count = try JSONEncoder().encode(archive).count
            print("BACKUP_BENCHMARK variant=legacy output_bytes=\(count)")
            return count
        }
    }

    func testIncrementalV1() throws {
        let sample = try Sample()
        record {
            let count = try V1BackupWriter.encode(books: sample.books, removedBooks: [], preferences: ReadingPreferences(),
                bookmarks: [], annotations: [], drafts: [], contentsURL: { sample.url($0) }).count
            print("BACKUP_BENCHMARK variant=v1 output_bytes=\(count)")
            return count
        }
    }

    func testFileV2() throws {
        let sample = try Sample()
        record {
            let result = try BackupContainer.export(books: sample.books, removedBooks: [], preferences: ReadingPreferences(),
                bookmarks: [], annotations: [], drafts: [], contentsURL: { sample.url($0) })
            let count = try BoundedBackupInput.fileSize(result.url)
            print("BACKUP_BENCHMARK variant=v2 output_bytes=\(count)")
            return count
        }
    }
}
