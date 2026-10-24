import XCTest

@MainActor
final class BackupProviderTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func launch(library: String, provider: String, role: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["INTERLINE_UI_TESTING"] = "1"
        app.launchEnvironment["INTERLINE_UI_TEST_SUITE"] = library
        app.launchEnvironment["INTERLINE_UI_PROVIDER_SUITE"] = provider
        app.launchEnvironment["INTERLINE_UI_BACKUP_ROLE"] = role
        app.launch()
        XCTAssertTrue(app.buttons["importBook"].firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func tapSettled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        var frame = element.frame
        var stableSince = Date()
        let ready = expectation(for: NSPredicate { _, _ in
            guard element.exists, element.isHittable, element.frame == frame else {
                frame = element.exists ? element.frame : .null
                stableSince = Date(); return false
            }
            return Date().timeIntervalSince(stableSince) >= 0.3
        }, evaluatedWith: element)
        wait(for: [ready], timeout: 20)
        element.tap()
    }

    private func storage(_ app: XCUIApplication) {
        tapSettled(app.buttons["libraryMenu"])
        tapSettled(app.buttons["数据与存储"])
        XCTAssertTrue(app.buttons["restoreLibraryBackup"].waitForExistence(timeout: 15))
    }

    private func providerFolder(_ app: XCUIApplication, suite: String) {
        let name = "InterlineQ01-" + suite
        let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        let ready = expectation(for: NSPredicate { _, _ in folder.exists || title.exists }, evaluatedWith: app)
        wait(for: [ready], timeout: 40)
        if folder.exists { tapSettled(folder) }
    }

    private func chooseBackup(_ app: XCUIApplication, suite: String, stem: String = "Interline-完整备份") {
        tapSettled(app.buttons["restoreLibraryBackup"])
        XCTAssertTrue(app.descendants(matching: .any)["Browse View (Picker)"].firstMatch.waitForExistence(timeout: 40))
        providerFolder(app, suite: suite)
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", stem)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 20), app.debugDescription)
        capture("FP05SelectExportedBackup")
        tapSettled(file)
        XCTAssertTrue(app.buttons["合并恢复"].waitForExistence(timeout: 30), app.debugDescription)
    }

    private func checkDraft(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FP05 retained draft")).firstMatch
        for _ in 0..<5 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        tapSettled(row)
        let editor = app.textViews["noteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertEqual(editor.value as? String, "FP05 retained draft")
        capture("FP05RestoredDraft")
        tapSettled(app.buttons["取消"])
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [dismissed], timeout: 20)
        tapSettled(app.buttons["完成"])
    }

    func testV2ExportCancelRestoreAndCurrentRecordWins() {
        let provider = UUID().uuidString
        let source = launch(library: UUID().uuidString, provider: provider, role: "source")
        XCTAssertTrue(source.buttons["continueReading"].label.contains("FP05 Backup Source"))
        storage(source)
        tapSettled(source.buttons["exportLibraryBackup"])
        XCTAssertTrue(source.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 40))
        providerFolder(source, suite: provider)
        capture("FP05ActualExportSave")
        tapSettled(source.buttons["DOCPicker.actionButton"])
        let exported = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: source.buttons["exportLibraryBackup"])
        wait(for: [exported], timeout: 30)
        source.terminate()

        let app = launch(library: UUID().uuidString, provider: provider, role: "destination")
        XCTAssertTrue(app.staticTexts["书架是空的"].exists)
        storage(app)
        chooseBackup(app, suite: provider)
        capture("FP05CancelConfirmation")
        // iOS 27 presents this confirmation as a popover without a Cancel
        // button. Its actual cancellation gesture is a tap outside the popover.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        let cancelled = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["合并恢复"])
        wait(for: [cancelled], timeout: 15)
        tapSettled(app.buttons["完成"])
        XCTAssertTrue(app.staticTexts["书架是空的"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["continueReading"].exists)
        storage(app)
        chooseBackup(app, suite: provider)
        tapSettled(app.buttons["合并恢复"])
        // The restored draft is evidence that the asynchronous merge completed.
        checkDraft(app)
        app.terminate(); app.launch()
        let resume = app.buttons["continueReading"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        XCTAssertTrue(resume.label.contains("FP05 Backup Source"))
        XCTAssertTrue(resume.label.contains("第二章 归途"))
        tapSettled(app.buttons["FP05 Backup Source的书籍详情"])
        let title = app.textFields["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (title.value as? String ?? "").count) + "FP05 Current Title")
        tapSettled(app.buttons["saveBookMetadata"])
        tapSettled(app.buttons["完成"])
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        storage(app)
        chooseBackup(app, suite: provider)
        tapSettled(app.buttons["合并恢复"])
        checkDraft(app)
        app.terminate(); app.launch()
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        XCTAssertTrue(resume.label.contains("FP05 Current Title"), resume.label)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCover-'" )).count, 1)
        checkReader(app, format: "v2")
    }

    private func checkReader(_ app: XCUIApplication, format: String) {
        tapSettled(app.buttons["continueReading"])
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        let body = expectation(for: NSPredicate(format: "exists == true AND label CONTAINS %@ AND label CONTAINS %@", "第二章 归途", "取消和失败后，原书、笔记和草稿仍应保留。"), evaluatedWith: canvas)
        wait(for: [body], timeout: 20)
        capture("FP05RestoredSecondChapter-" + format)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tapSettled(app.buttons["readerSettings"])
        XCTAssertTrue(app.staticTexts["22"].waitForExistence(timeout: 15))
        capture("FP05RestoredFontSize-" + format)
        tapSettled(app.buttons["完成"])
        tapSettled(app.buttons["readerTOC"])
        tapSettled(app.segmentedControls.buttons["书签 (1)"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "第二章 归途")).firstMatch.waitForExistence(timeout: 15))
        capture("FP05RestoredBookmark-" + format)
        tapSettled(app.segmentedControls.buttons["笔记 (1)"])
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FP05 retained note")).firstMatch.waitForExistence(timeout: 15))
        capture("FP05RestoredSingleNote-" + format)
    }

    func testV1WriterFileSelectionAndRepeatedRestore() {
        let provider = UUID().uuidString
        let source = launch(library: UUID().uuidString, provider: provider, role: "source-v1")
        XCTAssertTrue(source.buttons["continueReading"].label.contains("FP05 Backup Source"))
        capture("FP05V1WriterSourceLibrary")
        source.terminate()
        let app = launch(library: UUID().uuidString, provider: provider, role: "destination-v1")
        XCTAssertTrue(app.staticTexts["书架是空的"].exists)
        for _ in 0..<2 {
            storage(app)
            chooseBackup(app, suite: provider, stem: "FP05-v1")
            tapSettled(app.buttons["合并恢复"])
            checkDraft(app)
            app.terminate(); app.launch()
            let resume = app.buttons["continueReading"]
            XCTAssertTrue(resume.waitForExistence(timeout: 20))
            XCTAssertTrue(resume.label.contains("FP05 Backup Source"))
            XCTAssertTrue(resume.label.contains("第二章 归途"))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCover-'" )).count, 1)
        }
        checkReader(app, format: "v1")
    }
}
