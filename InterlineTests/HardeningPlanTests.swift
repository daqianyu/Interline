import XCTest
@testable import Interline

/// Regression evidence for plans/2026-10-improvements (D01, D02).
@MainActor
final class HardeningPlanTests: XCTestCase {
    @MainActor private struct Fixture {
        let name = "InterlineHardening-" + UUID().uuidString
        let defaults: UserDefaults
        let storage: ReadingStorage
        init() {
            defaults = UserDefaults(suiteName: name)!
            storage = ReadingStorage(defaults: defaults,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        }
        func clean() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: storage.directory)
        }
    }

    private let bookmarksKey = "interline_saved_bookmarks_v1"
    private let preferencesKey = "interline_saved_preferences_v1"

    private func book(_ suffix: String = "original") throws -> Book {
        try TXTImportService.parse(data: Data(("第一章\n" + String(repeating: "保护原始阅读资料。", count: 30) + suffix).utf8), fileName: suffix + ".txt").book
    }

    private func archivedDefaults(_ storage: ReadingStorage) throws -> [String: Any] {
        var values: [String: Any] = [:]
        for file in storage.recoveryFiles() where file.url.pathExtension == "plist" {
            let data = try Data(contentsOf: file.url)
            let archive = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let key = try XCTUnwrap(archive["key"] as? String)
            values[key] = try XCTUnwrap(archive["value"])
        }
        return values
    }

    // T-D01-01: a real bookmark action must preserve the unreadable previous bytes.
    func testAddingBookmarkArchivesCorruptDefaultsAndSurvivesRelaunch() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let damaged = Data("[{\"snippet\":\"旧书签\"},broken".utf8)
        f.defaults.set(damaged, forKey: bookmarksKey)
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        XCTAssertTrue(state.bookmarks.isEmpty)
        state.openBook(value); state.prepareReader(size: CGSize(width: 280, height: 400))
        state.toggleBookmark()
        let id = try XCTUnwrap(state.bookmarks.first?.id)
        XCTAssertEqual(try archivedDefaults(f.storage)[bookmarksKey] as? Data, damaged)
        XCTAssertEqual(AppState(storage: f.storage).bookmarks.map(\.id), [id])
        XCTAssertEqual(f.storage.recoveryFiles().count, 1)
    }

    // T-D01-02: preserve both a wrong property-list type and corrupt record bytes.
    func testInvalidPreferencesAndRecordKeepOriginalTypesAndBytes() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book()
        let oldPreferences = ["unexpected": ["旧设置", "仍需恢复"]]
        let recordKey = "interline_reading_record_v2_" + value.id
        let oldRecord = Data("damaged reading record".utf8)
        f.defaults.set(oldPreferences, forKey: preferencesKey)
        f.defaults.set(oldRecord, forKey: recordKey)
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences(fontSize: 22)))
        XCTAssertTrue(f.storage.saveRecord(for: value))
        let archived = try archivedDefaults(f.storage)
        XCTAssertEqual(archived[preferencesKey] as? [String: [String]], oldPreferences)
        XCTAssertEqual(archived[recordKey] as? Data, oldRecord)
        XCTAssertEqual(f.storage.loadPreferences().fontSize, 22)
        XCTAssertNotNil(f.storage.loadRecord(bookID: value.id))
        XCTAssertEqual(f.storage.recoveryFiles().count, 2)
    }

    // T-D01-03: an unavailable recovery folder must leave every original untouched.
    func testFailedDefaultsArchiveRefusesWritesAndVisibleBookmarkChange() throws {
        let f = Fixture(); defer { f.clean() }
        let value = try book(); XCTAssertTrue(f.storage.saveBooks([value]))
        let recordKey = "interline_reading_record_v2_" + value.id
        let damaged = Data("unreadable original".utf8)
        for key in [bookmarksKey, preferencesKey, recordKey] { f.defaults.set(damaged, forKey: key) }
        let barrier = f.storage.directory.appendingPathComponent("Recovery")
        try Data("blocked".utf8).write(to: barrier)
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        state.openBook(value); state.prepareReader(size: CGSize(width: 280, height: 400))
        state.toggleBookmark()
        XCTAssertTrue(state.bookmarks.isEmpty)
        XCTAssertEqual(state.notice?.isError, true)
        XCTAssertFalse(f.storage.savePreferences(ReadingPreferences()))
        XCTAssertFalse(f.storage.saveRecord(for: value))
        for key in [bookmarksKey, preferencesKey, recordKey] { XCTAssertEqual(f.defaults.data(forKey: key), damaged) }
        XCTAssertEqual(try Data(contentsOf: barrier), Data("blocked".utf8))
    }

    // T-D01-04: healthy data must not create a recovery copy on each ordinary write.
    func testValidDefaultsUpdatesDoNotCreateRecoveryCopies() throws {
        let f = Fixture(); defer { f.clean() }
        var value = try book()
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences()))
        XCTAssertTrue(f.storage.saveBookmarks([]))
        XCTAssertTrue(f.storage.saveRecord(for: value))
        value.lastReadDate = Date(timeIntervalSince1970: 123)
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences(fontSize: 21)))
        XCTAssertTrue(f.storage.saveBookmarks([]))
        XCTAssertTrue(f.storage.saveRecord(for: value))
        XCTAssertEqual(f.storage.loadPreferences().fontSize, 21)
        XCTAssertEqual(f.storage.loadRecord(bookID: value.id)?.lastReadDate, value.lastReadDate)
        XCTAssertTrue(f.storage.recoveryFiles().isEmpty)
    }

    // T-D02-01/02: replay a partially written transaction whose rollback is blocked.
    func testFailedRollbackRemainsBlockedUntilRecoveryCanActuallyFinish() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = try book(), other = try book("other")
        let note = ReadingAnnotation(bookID: original.id, chapterID: original.chapters[0].id,
            range: NSRange(location: 0, length: 3), quote: "第一章", note: "事务前的笔记")
        XCTAssertTrue(f.storage.saveBooks([original]))
        XCTAssertTrue(f.storage.saveAnnotations([note]))
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences(fontSize: 19)))
        let state = AppState(storage: f.storage)
        let backup = try await state.exportLibraryBackup()

        try f.storage.beginTransaction()
        XCTAssertTrue(f.storage.saveBooks([other]))
        XCTAssertTrue(f.storage.saveAnnotations([]))
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences(fontSize: 25)))
        let notesURL = f.storage.directory.appendingPathComponent("annotations-v1.json")
        try FileManager.default.removeItem(at: notesURL)
        try FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: false)

        let success = await state.restoreLibraryBackup(backup)
        XCTAssertFalse(success)
        let notice = try XCTUnwrap(state.notice)
        XCTAssertTrue(notice.isError)
        XCTAssertTrue(notice.message.contains("回滚尚未成功"))
        XCTAssertFalse(notice.message.contains("原有资料已保留"))
        let journal = f.storage.directory.appendingPathComponent("restore-journal-v1.json")
        XCTAssertTrue(f.storage.recoveryFiles().contains { $0.url == journal })
        XCTAssertFalse(f.storage.saveBookmarks([]))

        try FileManager.default.removeItem(at: notesURL)
        state.retryInterruptedRestore()
        XCTAssertEqual(state.books.map(\.id), [original.id])
        XCTAssertEqual(state.annotations.first?.note, note.note)
        XCTAssertEqual(state.preferences.fontSize, 19)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertTrue(f.storage.saveBookmarks([]))
        XCTAssertEqual(state.notice?.isError, false)
    }

    // T-D02-03: report retained data only when the real rollback succeeded.
    func testSuccessfulRollbackRestoresDataBeforeReportingItPreserved() async throws {
        let f = Fixture(); defer { f.clean() }
        let original = try book(), other = try book("other")
        XCTAssertTrue(f.storage.saveBooks([original]))
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences(fontSize: 19)))
        let state = AppState(storage: f.storage)
        let backup = try await state.exportLibraryBackup()
        try f.storage.beginTransaction()
        XCTAssertTrue(f.storage.saveBooks([other]))
        XCTAssertTrue(f.storage.savePreferences(ReadingPreferences(fontSize: 25)))
        let success = await state.restoreLibraryBackup(backup)
        XCTAssertFalse(success)
        XCTAssertEqual(f.storage.loadBooks().map(\.id), [original.id])
        XCTAssertEqual(f.storage.loadPreferences().fontSize, 19)
        XCTAssertTrue(state.notice?.message.contains("原有资料已保留") == true)
        XCTAssertFalse(state.notice?.message.contains("回滚尚未成功") == true)
        XCTAssertTrue(f.storage.saveBookmarks([]))
    }
}
