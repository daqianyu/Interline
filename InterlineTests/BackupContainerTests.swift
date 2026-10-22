import XCTest
import UniformTypeIdentifiers
@testable import Interline

@MainActor
final class BackupContainerTests: XCTestCase {
    @MainActor private struct Fixture {
        let name = "BackupContainer-" + UUID().uuidString
        let defaults: UserDefaults
        let storage: ReadingStorage
        init() {
            defaults = UserDefaults(suiteName: name)!
            storage = ReadingStorage(defaults: defaults,
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            try! FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        }
        func clean() { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: storage.directory) }
    }
    private func book(_ id: String = "a") -> Book {
        Book(id: id, title: "书名\"" + id, author: "作者", chapters: [
            Chapter(id: "c", title: "第一章", content: ["中文 👩🏽‍💻 e\u{301}", "\"引号\"\\换行\n\u{0}"])
        ])
    }
    private func export(_ values: [Book], parent: URL = FileManager.default.temporaryDirectory,
                        limit: Int = ReadingStorage.maximumBackupBytes) throws -> BackupExport {
        try BackupContainer.export(books: values, removedBooks: [], preferences: ReadingPreferences(),
            bookmarks: [], annotations: [], drafts: [], createdAt: Date(timeIntervalSinceReferenceDate: 123),
            maximumBytes: limit, temporaryParent: parent, contentsURL: { _ in parent.appendingPathComponent("unused") })
    }
    private func unpack(_ data: Data) throws -> (BackupManifest, Data) {
        let prefix = Data("InterlineBackup2\n".utf8).count
        let length = data[prefix..<(prefix + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let start = prefix + 8, end = start + Int(length)
        return (try JSONDecoder().decode(BackupManifest.self, from: data.subdata(in: start..<end)), data.subdata(in: end..<data.count))
    }
    private func pack(_ manifest: BackupManifest, body: Data) throws -> Data {
        try packJSON(JSONEncoder().encode(manifest), body: body)
    }
    private func packJSON(_ json: Data, body: Data) throws -> Data {
        var bytes = Data("InterlineBackup2\n".utf8)
        var length = UInt64(json.count).bigEndian
        Swift.withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
        bytes.append(json); bytes.append(body)
        return bytes
    }
    private func prepare(_ bytes: Data, fixture: Fixture) throws -> PreparedLibraryBackup {
        let url = fixture.storage.directory.appendingPathComponent("input.interlinebackup")
        try bytes.write(to: url, options: .atomic)
        return try BackupContainer.prepare(url: url, temporaryParent: fixture.storage.directory)
    }

    func testV2RoundTripRestoresBooksRemovedNotesDraftsPreferencesAndPosition() async throws {
        let source = Fixture(), target = Fixture(); defer { source.clean(); target.clean() }
        var first = book(), removed = book("removed")
        first.readingLocation = ReadingLocation(chapterID: "c", utf16Offset: 8)
        first.visibleEndOffset = 12
        XCTAssertTrue(source.storage.saveBooks([first, removed]))
        let state = AppState(storage: source.storage, usesBackgroundLayout: false, loadsContentsOnDemand: true)
        state.updatePreferences { $0.fontSize = 22 }
        XCTAssertTrue(state.addAnnotation(bookID: first.id, chapterID: "c", range: NSRange(location: 0, length: 3), note: "完整笔记"))
        state.deleteBook(id: removed.id)
        let draft = NoteDraft(bookID: first.id, chapterID: "c", range: NSRange(location: 0, length: 3), quote: "第一章", text: "待保存草稿")
        XCTAssertTrue(state.queueDraft(draft))
        let file = try await state.exportLibraryBackupFile()
        let prepared = try BackupContainer.prepare(url: file.url)
        XCTAssertTrue(prepared.metadata.books.allSatisfy { $0.chapters.isEmpty })
        XCTAssertEqual(try prepared.readBook(prepared.metadata.books[0]).chapters, first.chapters)
        XCTAssertTrue(target.storage.saveBooks([]))
        let restored = AppState(storage: target.storage, usesBackgroundLayout: false)
        let success = await restored.restoreLibraryBackup(prepared)
        XCTAssertTrue(success)
        XCTAssertEqual(restored.books.map(\.id), [first.id])
        XCTAssertEqual(restored.books.first?.readingLocation, first.readingLocation)
        XCTAssertEqual(restored.annotations.first?.note, "完整笔记")
        XCTAssertEqual(restored.drafts.first?.text, draft.text)
        XCTAssertEqual(restored.preferences.fontSize, 22)
        XCTAssertEqual(restored.maintenance.removedBooks.map(\.id), [removed.id])
    }

    func testLegacyFileIsPreparedOnceAndRestoresThroughTheSameTransaction() async throws {
        let f = Fixture(); defer { f.clean() }
        let value = book()
        let legacy = LibraryBackup(version: 1, createdAt: Date(), books: [value], removedBooks: [],
            preferences: ReadingPreferences(fontSize: 23), bookmarks: [], annotations: [], drafts: [])
        let url = f.storage.directory.appendingPathComponent("legacy.json")
        try JSONEncoder().encode(legacy).write(to: url)
        let prepared = try BackupContainer.prepare(url: url)
        XCTAssertEqual(try prepared.readBook(prepared.metadata.books[0]).chapters, value.chapters)
        XCTAssertTrue(f.storage.saveBooks([]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        let success = await state.restoreLibraryBackup(prepared)
        XCTAssertTrue(success)
        XCTAssertEqual(state.books.first?.chapters, value.chapters)
        XCTAssertEqual(state.preferences.fontSize, 23)
    }

    func testEmptyV2CanRoundTrip() throws {
        let file = try export([])
        let prepared = try BackupContainer.prepare(url: file.url)
        XCTAssertTrue(prepared.metadata.books.isEmpty)
        XCTAssertTrue(prepared.manifest.entries.isEmpty)
    }

    func testWrongVersionPartialAndInvalidEntryMappingAreRejected() throws {
        let f = Fixture(); defer { f.clean() }
        let file = try export([book()])
        let (original, body) = try unpack(Data(contentsOf: file.url))
        var bad = original; bad.version = 99
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
        bad = original; bad.complete = false
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
        bad = original; bad.entries = []
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
        bad = original; bad.books.append(bad.books[0]); bad.entries.append(bad.entries[0])
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
        bad = original; bad.books[0].chapters = book().chapters
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
    }

    func testHashMismatchTruncationTrailingBytesAndHugeLengthsAreRejected() throws {
        let f = Fixture(); defer { f.clean() }
        let file = try export([book()])
        let bytes = try Data(contentsOf: file.url)
        let (manifest, body) = try unpack(bytes)
        var changed = body; changed[changed.startIndex] ^= 1
        XCTAssertThrowsError(try prepare(pack(manifest, body: changed), fixture: f))
        XCTAssertThrowsError(try prepare(Data(bytes.dropLast()), fixture: f))
        XCTAssertThrowsError(try prepare(bytes + Data([0]), fixture: f))
        var huge = Data("InterlineBackup2\n".utf8); huge.append(Data(repeating: 255, count: 8))
        XCTAssertThrowsError(try prepare(huge, fixture: f))
        var bad = manifest
        bad.entries = [.init(bookID: "a", byteCount: Int.max, sha256: manifest.entries[0].sha256)]
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
        bad.entries = [.init(bookID: "a", byteCount: -1, sha256: manifest.entries[0].sha256)]
        XCTAssertThrowsError(try prepare(pack(bad, body: body), fixture: f))
    }

    func testValidHashDoesNotAllowInvalidBodyOrMismatchedQuote() throws {
        let f = Fixture(); defer { f.clean() }
        let file = try export([book()])
        let (manifest, body) = try unpack(Data(contentsOf: file.url))
        for invalid in [Data("not JSON".utf8), Data("[]".utf8), try JSONEncoder().encode([book().chapters[0], book().chapters[0]])] {
            var bad = manifest
            bad.entries = [.init(bookID: "a", byteCount: invalid.count, sha256: BackupContainer.digest(invalid))]
            XCTAssertThrowsError(try prepare(pack(bad, body: invalid), fixture: f))
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        let note = ReadingAnnotation(bookID: "a", chapterID: "c", range: NSRange(location: 0, length: 3), quote: "不匹配")
        object["annotations"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([note]))
        XCTAssertThrowsError(try prepare(packJSON(JSONSerialization.data(withJSONObject: object), body: body), fixture: f))
    }

    func testTemporaryFilesLiveUntilTheirOwnerIsReleasedAndFailuresCleanUp() throws {
        let f = Fixture(); defer { f.clean() }
        var file: BackupExport? = try export([book()], parent: f.storage.directory)
        let directory = try XCTUnwrap(file?.url.deletingLastPathComponent())
        var prepared: PreparedLibraryBackup? = try BackupContainer.prepare(url: XCTUnwrap(file?.url), temporaryParent: f.storage.directory)
        let preparedDirectory = try XCTUnwrap(prepared?.workspace.directory)
        file = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preparedDirectory.path))
        XCTAssertEqual(try prepared?.readBook(book().metadata).chapters, book().chapters)
        prepared = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedDirectory.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.storage.directory.path).isEmpty)
        let value = book()
        let normal = try export([value])
        let size = try BoundedBackupInput.fileSize(normal.url)
        XCTAssertThrowsError(try export([value], parent: f.storage.directory, limit: size - 1))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.storage.directory.path).isEmpty)
    }

    func testV2MergeKeepsCurrentMetadataAndRejectsDifferentExistingBody() async throws {
        let f = Fixture(); defer { f.clean() }
        var value = book(); value.title = "当前书名"
        XCTAssertTrue(f.storage.saveBooks([value]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        let file = try export([book()]), prepared = try BackupContainer.prepare(url: file.url)
        let first = await state.restoreLibraryBackup(prepared), again = await state.restoreLibraryBackup(prepared)
        XCTAssertTrue(first && again)
        XCTAssertEqual(state.books.first?.title, value.title)
        let catalog = try Data(contentsOf: f.storage.catalogURL)
        var different = book(); different.chapters[0].content = ["另一份正文"]
        let badFile = try export([different]), bad = try BackupContainer.prepare(url: badFile.url)
        let failed = await state.restoreLibraryBackup(bad)
        XCTAssertFalse(failed)
        XCTAssertEqual(try Data(contentsOf: f.storage.catalogURL), catalog)
    }

    func testPreparedBodyTamperingRefusesRestoreAndLeavesCatalogUnchanged() async throws {
        let f = Fixture(); defer { f.clean() }
        XCTAssertTrue(f.storage.saveBooks([]))
        let state = AppState(storage: f.storage, usesBackgroundLayout: false)
        let file = try export([book()]), prepared = try BackupContainer.prepare(url: file.url)
        try Data("bad bytes".utf8).write(to: prepared.workspace.bodyURL(0), options: .atomic)
        let before = try Data(contentsOf: f.storage.catalogURL)
        let success = await state.restoreLibraryBackup(prepared)
        XCTAssertFalse(success)
        XCTAssertEqual(try Data(contentsOf: f.storage.catalogURL), before)
        XCTAssertTrue(state.books.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.storage.directory.appendingPathComponent("restore-journal-v1.json").path))
    }

    func testUntrustedChapterSummariesAreRebuiltFromValidatedBody() throws {
        let f = Fixture(); defer { f.clean() }
        let file = try export([book()]), (manifest, body) = try unpack(Data(contentsOf: file.url))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        var headers = try XCTUnwrap(object["books"] as? [[String: Any]])
        headers[0]["chapterSummaries"] = [["id": "c", "title": "伪造标题", "readingLength": Int.max, "characterCount": Int.max]]
        object["books"] = headers
        let prepared = try prepare(packJSON(JSONSerialization.data(withJSONObject: object), body: body), fixture: f)
        XCTAssertEqual(prepared.metadata.books[0].summaries, book().summaries)
    }

    func testWorkerCancellationDoesNotCreateFiles() async throws {
        let f = Fixture(); defer { f.clean() }
        let parent = f.storage.directory
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await BackupWorker.run { try BackupWorkspace(parent: parent) }; return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.storage.directory.path).isEmpty)
    }

    func testBackupFileTypeIsRegisteredInTheBuiltApp() throws {
        XCTAssertEqual(UTType(filenameExtension: "interlinebackup"), .interlineBackup)
        let types = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        XCTAssertTrue(types.contains { $0["UTTypeIdentifier"] as? String == "com.interline.backup" })
    }
}
