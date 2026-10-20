import XCTest
@testable import Interline

@MainActor
final class ReviewRegressionTests: XCTestCase {
    private func fixture() throws -> (ReadingStorage, UserDefaults, String) {
        let name = "InterlineReview-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (ReadingStorage(defaults: defaults, directory: directory), defaults, name)
    }

    private func clean(_ storage: ReadingStorage, _ defaults: UserDefaults, _ name: String) {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: storage.directory)
    }

    private func book(_ text: String = "第一章\n测试正文") throws -> Book {
        try TXTImportService.parse(data: Data(text.utf8), fileName: "回归.txt").book
    }

    private func backups(_ storage: ReadingStorage) throws -> [Data] {
        let directory = storage.directory.appendingPathComponent("Recovery")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { try Data(contentsOf: $0) }
    }

    func testCorruptCatalogIsBackedUpBeforeSubsequentImport() async throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        XCTAssertTrue(storage.saveBooks([try book()]))
        let damaged = Data("{\"books\":[\"recoverable-original\"],broken".utf8)
        try damaged.write(to: storage.catalogURL)
        let state = AppState(storage: storage)
        XCTAssertTrue(state.books.isEmpty)
        let imported = await state.importBook(try book("第二章\n新书"))
        XCTAssertTrue(imported)
        XCTAssertEqual(try backups(storage), [damaged])
        XCTAssertEqual(storage.loadBooks().count, 1)
    }

    func testCorruptNotesAreBackedUpBeforeAddingAnnotation() throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book()
        XCTAssertTrue(storage.saveBooks([value]))
        let damaged = Data("[{\"quote\":\"old note\"},broken".utf8)
        try damaged.write(to: storage.directory.appendingPathComponent("annotations-v1.json"))
        let state = AppState(storage: storage)
        XCTAssertTrue(state.annotations.isEmpty)
        XCTAssertTrue(state.addAnnotation(bookID: value.id, chapterID: value.chapters[0].id, range: NSRange(location: 0, length: 3)))
        XCTAssertEqual(try backups(storage), [damaged])
        XCTAssertEqual(storage.loadAnnotations().count, 1)
    }

    func testFailedRecoveryBackupRefusesCatalogAndNotesOverwrite() throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book()
        XCTAssertTrue(storage.saveBooks([value]))
        let damaged = Data("damaged original".utf8)
        let notesURL = storage.directory.appendingPathComponent("annotations-v1.json")
        try damaged.write(to: storage.catalogURL)
        try damaged.write(to: notesURL)
        // A regular file prevents creation of the Recovery directory.
        try Data("blocked".utf8).write(to: storage.directory.appendingPathComponent("Recovery"))
        XCTAssertFalse(storage.saveBooks([value]))
        XCTAssertFalse(storage.saveAnnotations([]))
        XCTAssertEqual(try Data(contentsOf: storage.catalogURL), damaged)
        XCTAssertEqual(try Data(contentsOf: notesURL), damaged)
    }

    func testValidFilesDoNotCreateRecoveryCopies() throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book()
        XCTAssertTrue(storage.saveBooks([value]))
        XCTAssertTrue(storage.saveBooks([value]))
        XCTAssertTrue(storage.saveAnnotations([]))
        XCTAssertTrue(storage.saveAnnotations([]))
        XCTAssertTrue(try backups(storage).isEmpty)
    }

    func testOpeningMissingBookDoesNotOverwriteAnchorBeforeRepair() async throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book("第一章\n" + String(repeating: "保留阅读位置。", count: 500))
        XCTAssertTrue(storage.saveBooks([value]))
        let state = AppState(storage: storage, usesBackgroundLayout: false)
        state.openBook(value)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        state.nextPage()
        let anchor = try XCTUnwrap(state.activeBook?.readingLocation)
        try FileManager.default.removeItem(at: storage.contentsURL(bookID: value.id))
        let broken = AppState(storage: storage, usesBackgroundLayout: false)
        XCTAssertEqual(broken.books[0].readingLocation, anchor)
        broken.openBook(broken.books[0])
        XCTAssertFalse(broken.isReaderPresented)
        XCTAssertEqual(storage.loadRecord(bookID: value.id)?.location, anchor)
        let repaired = await broken.importBook(value)
        XCTAssertTrue(repaired)
        XCTAssertEqual(broken.books[0].readingLocation, anchor)
    }

    func testUndoFailureRetainsCommittedStateAndAllowsRetry() throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book()
        XCTAssertTrue(storage.saveBooks([value]))
        let state = AppState(storage: storage)
        state.deleteBook(id: value.id)
        XCTAssertTrue(state.books.isEmpty)
        let catalog = try Data(contentsOf: storage.catalogURL)
        try FileManager.default.removeItem(at: storage.catalogURL)
        try FileManager.default.createDirectory(at: storage.catalogURL, withIntermediateDirectories: false)
        state.undoDelete()
        XCTAssertTrue(state.books.isEmpty)
        XCTAssertTrue(state.canUndoDelete)
        XCTAssertTrue(state.toastMessage?.contains("撤销移出失败") == true)
        try FileManager.default.removeItem(at: storage.catalogURL)
        try catalog.write(to: storage.catalogURL)
        state.undoDelete()
        XCTAssertEqual(state.books.map(\.id), [value.id])
        XCTAssertFalse(state.canUndoDelete)
        XCTAssertEqual(storage.loadBooks().map(\.id), [value.id])
    }

    func testFailedRemovalDoesNotChangeBookshelfOrReader() throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book()
        XCTAssertTrue(storage.saveBooks([value]))
        let state = AppState(storage: storage)
        state.openBook(value)
        try FileManager.default.removeItem(at: storage.catalogURL)
        try FileManager.default.createDirectory(at: storage.catalogURL, withIntermediateDirectories: false)
        state.deleteBook(id: value.id)
        XCTAssertEqual(state.books.map(\.id), [value.id])
        XCTAssertTrue(state.isReaderPresented)
        XCTAssertFalse(state.canUndoDelete)
        XCTAssertNotNil(state.toastMessage)
    }

    func testSplitSpecialAndLongHeadingsSurviveExportImport() throws {
        let headings = ["序章", "序言", "前言", "楔子", "尾声", "后记", "正文",
                        "第一章 " + String(repeating: "长", count: 49),
                        "Chapter 1 " + String(repeating: "A", count: 49)]
        for heading in headings {
            let original = try book(heading + "\n" + String(repeating: "长篇内容。", count: 15_000))
            XCTAssertGreaterThan(original.chapters.count, 1)
            let exported = original.chapters.map(\.readingText).joined(separator: "\n\n")
            let reimported = try book(exported)
            XCTAssertEqual(reimported.id, original.id, heading)
            XCTAssertEqual(reimported.chapters.map(\.readingText), original.chapters.map(\.readingText), heading)
        }
    }

    func testSelectionSnapshotKeepsTextAndAnchorAcrossReflow() throws {
        let (storage, defaults, name) = try fixture()
        defer { clean(storage, defaults, name) }
        let value = try book("第一章\n" + String(repeating: "分页与标注。", count: 900))
        XCTAssertTrue(storage.saveBooks([value]))
        let state = AppState(storage: storage, usesBackgroundLayout: false)
        state.openBook(value)
        state.prepareReader(size: CGSize(width: 300, height: 400))
        state.nextPage()
        state.presentTextSelection()
        let snapshot = try XCTUnwrap(state.selectionSnapshot)
        state.prepareReader(size: CGSize(width: 600, height: 250))
        state.updatePreferences { $0.fontSize += 3 }
        XCTAssertEqual(state.selectionSnapshot?.id, snapshot.id)
        XCTAssertEqual(state.selectionSnapshot?.text, snapshot.text)
        XCTAssertEqual(state.selectionSnapshot?.page, snapshot.page)
        let range = NSRange(location: snapshot.page.range.location, length: 1)
        XCTAssertTrue(state.addAnnotation(bookID: snapshot.bookID, chapterID: snapshot.page.chapterID, range: range))
        XCTAssertEqual(state.annotations.last?.quote, String(snapshot.text.prefix(1)))
        state.closeReader()
        XCTAssertNil(state.selectionSnapshot)
    }
}
