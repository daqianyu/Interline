import XCTest

@MainActor
final class ReaderFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Accessibility existence alone does not mean an animating toolbar has
    /// reached its touch location. Observe the actual frame; do not sleep or retry taps.
    private func tapSettled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        var previousFrame = element.frame
        var stableSince = Date()
        let settled = NSPredicate { _, _ in
            guard element.exists, element.isHittable else {
                previousFrame = .null
                stableSince = Date()
                return false
            }
            let frame = element.frame
            if frame != previousFrame {
                previousFrame = frame
                stableSince = Date()
                return false
            }
            return Date().timeIntervalSince(stableSince) >= 0.3
        }
        let ready = expectation(for: settled, evaluatedWith: element)
        wait(for: [ready], timeout: 15)
        element.tap()
    }

    private func launch(failNoteSave: Bool = false, failDraftSave: Bool = false, blockCatalog: Bool = false, largeDark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["INTERLINE_UI_TESTING"] = "1"
        app.launchEnvironment["INTERLINE_UI_TEST_SUITE"] = UUID().uuidString
        if largeDark {
            app.launchEnvironment["INTERLINE_UI_DARK_APPEARANCE"] = "1"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        if blockCatalog { app.launchEnvironment["INTERLINE_UI_BLOCK_CATALOG"] = "1" }
        if failNoteSave { app.launchEnvironment["INTERLINE_UI_FAIL_NOTE_SAVE"] = "1" }
        if failDraftSave { app.launchEnvironment["INTERLINE_UI_FAIL_DRAFT_SAVE"] = "1" }
        app.launch()
        return app
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testBookshelfReaderAndTypographyControls() {
        let app = launch()
        XCTAssertTrue(app.buttons["importBook"].firstMatch.waitForExistence(timeout: 15))
        screenshot(app, name: "Bookshelf")
        app.buttons["continueReading"].tap()
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        // Let initial pagination complete before bringing up the toolbars.
        let ready = expectation(for: NSPredicate(format: "label != %@ AND label.length > 20", "正在排版"), evaluatedWith: canvas)
        wait(for: [ready], timeout: 15)
        screenshot(app, name: "Reader")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["readerSettings"].waitForExistence(timeout: 5))
        app.buttons["readerSettings"].tap()
        XCTAssertTrue(app.sliders["行距"].waitForExistence(timeout: 5))
        screenshot(app, name: "Typography")
    }

    func testFullTextSearchReturnsToReader() {
        let app = launch()
        app.buttons["continueReading"].tap()
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["readerSearch"].waitForExistence(timeout: 5))
        app.buttons["readerSearch"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("引力")
        let result = app.buttons["searchMatch"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        screenshot(app, name: "Search")
        result.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    }

    func testSelectionSurfaceAndNotesTabAreReachable() {
        let app = launch()
        app.buttons["continueReading"].tap()
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        let ready = expectation(for: NSPredicate(format: "label != %@ AND label.length > 20", "正在排版"), evaluatedWith: canvas)
        wait(for: [ready], timeout: 15)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        canvas.press(forDuration: 0.8)
        XCTAssertTrue(app.textViews["selectableText"].waitForExistence(timeout: 5))
        screenshot(app, name: "Selection")
        app.buttons["完成"].tap()
        if !app.buttons["readerTOC"].exists { canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["readerTOC"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["笔记 (0)"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["笔记 (0)"].tap()
        XCTAssertTrue(app.staticTexts["暂无标注或笔记"].waitForExistence(timeout: 5))
    }

    func testSelectionTextRemainsStableWhenDeviceRotates() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch()
        app.buttons["continueReading"].tap()
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        let ready = expectation(for: NSPredicate(format: "label != %@ AND label.length > 20", "正在排版"), evaluatedWith: canvas)
        wait(for: [ready], timeout: 15)
        canvas.press(forDuration: 0.8)
        let selection = app.textViews["selectableText"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let original = selection.value as? String
        XCTAssertFalse(original?.isEmpty ?? true)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        XCTAssertEqual(selection.value as? String, original)
        screenshot(app, name: "SelectionLandscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(selection.value as? String, original)
        app.buttons["完成"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
    }


    private func readyCanvas(_ app: XCUIApplication) -> XCUIElement {
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let ready = expectation(for: NSPredicate(format: "label != %@ AND label.length > 20", "正在排版"), evaluatedWith: canvas)
        wait(for: [ready], timeout: 20)
        return canvas
    }

    private func beginNote(_ app: XCUIApplication) {
        app.buttons["continueReading"].tap()
        let canvas = readyCanvas(app)
        canvas.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["selectParagraph"].waitForExistence(timeout: 5))
        app.buttons["selectParagraph"].tap()
        app.buttons["writeNote"].tap()
        XCTAssertTrue(app.textViews["noteEditor"].waitForExistence(timeout: 5))
    }

    func testNoteCanBeWrittenAndPersistedThroughRelaunch() {
        let app = launch()
        beginNote(app)
        let editor = app.textViews["noteEditor"]
        editor.tap(); editor.typeText("A reading note")
        app.buttons["saveNote"].tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [dismissed], timeout: 15)
        let selectionDismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.textViews["selectableText"])
        wait(for: [selectionDismissed], timeout: 15)
        _ = readyCanvas(app)
        app.terminate(); app.launch()
        app.buttons["continueReading"].tap()
        let canvas = readyCanvas(app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tapSettled(app.buttons["readerTOC"])
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5), "目录弹窗未呈现")
        XCTAssertTrue(app.segmentedControls.buttons["笔记 (1)"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["笔记 (1)"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A reading note")).firstMatch.waitForExistence(timeout: 5))
        screenshot(app, name: "SavedNotes")
    }

    func testFailedNoteSaveKeepsEditorAndInputVisible() {
        let app = launch(failNoteSave: true)
        // Dismiss the persistent startup warning before using the reader.
        if app.buttons["关闭提示"].exists { app.buttons["关闭提示"].tap() }
        beginNote(app)
        let editor = app.textViews["noteEditor"]
        editor.tap(); editor.typeText("Keep this draft")
        app.buttons["saveNote"].tap()
        XCTAssertTrue(app.staticTexts["noteSaveError"].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Keep this draft")
        XCTAssertTrue(app.buttons["saveNote"].exists)
        screenshot(app, name: "NoteSaveFailure")
    }

    func testCancelledDraftSurvivesRelaunchAndCanBeResumed() {
        let app = launch()
        beginNote(app)
        let editor = app.textViews["noteEditor"]
        editor.tap(); editor.typeText("Retained draft")
        let status = app.staticTexts["draftSaveStatus"]
        let saved = expectation(for: NSPredicate(format: "label == %@", "已保存"), evaluatedWith: status)
        wait(for: [saved], timeout: 15)
        app.buttons["取消"].tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [dismissed], timeout: 10)
        app.terminate(); app.launch()
        app.buttons["libraryMenu"].tap()
        app.buttons["数据与存储"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Retained draft")).firstMatch
        for _ in 0..<4 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, "Retained draft")
        XCTAssertEqual(status.label, "已保存")
        screenshot(app, name: "ResumedDraft")
        app.buttons["saveNote"].tap()
        let committed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [committed], timeout: 15)
        app.terminate(); app.launch()
        app.buttons["continueReading"].tap()
        let canvas = readyCanvas(app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tapSettled(app.buttons["readerTOC"])
        XCTAssertTrue(app.segmentedControls.buttons["笔记 (1)"].waitForExistence(timeout: 10))
        app.segmentedControls.buttons["笔记 (1)"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Retained draft")).firstMatch.waitForExistence(timeout: 10))
        screenshot(app, name: "CommittedResumedDraft")
    }

    func testDraftCommitCanBeCancelledWhileReading() {
        let app = launch()
        beginNote(app)
        let editor = app.textViews["noteEditor"]
        editor.tap(); editor.typeText("Cancel reading without losing input")
        app.buttons["取消"].tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: editor)
        wait(for: [dismissed], timeout: 15)
        app.terminate()
        app.launchEnvironment["INTERLINE_UI_DELAY_CONTENTS"] = "1"
        app.launch()
        app.buttons["libraryMenu"].tap()
        app.buttons["数据与存储"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Cancel reading without losing input")).firstMatch
        for _ in 0..<5 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        app.buttons["saveNote"].tap()
        XCTAssertTrue(app.staticTexts["noteCommitStatus"].waitForExistence(timeout: 10))
        screenshot(app, name: "DraftChapterLoading")
        app.buttons["取消保存"].tap()
        let cancelled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["saveNote"])
        wait(for: [cancelled], timeout: 15)
        XCTAssertEqual(editor.value as? String, "Cancel reading without losing input")
        XCTAssertEqual(app.staticTexts["draftSaveStatus"].label, "已保存")
        XCTAssertFalse(app.staticTexts["noteSaveError"].exists)
        screenshot(app, name: "DraftChapterCancelled")
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "INTERLINE_UI_DELAY_CONTENTS")
        app.launch()
        app.buttons["continueReading"].tap()
        let canvas = readyCanvas(app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        tapSettled(app.buttons["readerTOC"])
        XCTAssertTrue(app.segmentedControls.buttons["笔记 (0)"].waitForExistence(timeout: 10))
    }

    func testFailedDraftSaveShowsRetryAndCancelKeepsInput() {
        let app = launch(failDraftSave: true)
        if app.buttons["关闭提示"].exists { app.buttons["关闭提示"].tap() }
        beginNote(app)
        let editor = app.textViews["noteEditor"]
        editor.tap(); editor.typeText("Do not lose this input")
        XCTAssertTrue(app.staticTexts["noteSaveError"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["draftSaveStatus"].label, "未保存")
        XCTAssertTrue(app.buttons["retryDraftSave"].exists)
        app.buttons["取消"].tap()
        let finished = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["saveNote"])
        wait(for: [finished], timeout: 15)
        XCTAssertEqual(editor.value as? String, "Do not lose this input")
        XCTAssertEqual(app.staticTexts["draftSaveStatus"].label, "未保存")
        screenshot(app, name: "DraftSaveFailure")
    }

    func testDataAndStorageManagementIsReachable() {
        let app = launch()
        app.buttons["libraryMenu"].tap()
        app.buttons["数据与存储"].tap()
        XCTAssertTrue(app.buttons["exportLibraryBackup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["restoreLibraryBackup"].exists)
        screenshot(app, name: "LibraryData")
    }

    func testFileBackupExportAndImportPickersCanBeCancelled() {
        let app = launch()
        app.buttons["libraryMenu"].tap()
        app.buttons["数据与存储"].tap()
        XCTAssertTrue(app.staticTexts["backupFormatHelp"].waitForExistence(timeout: 10))
        app.buttons["exportLibraryBackup"].tap()
        XCTAssertTrue(app.buttons["DOCPicker.actionButton"].waitForExistence(timeout: 20))
        screenshot(app, name: "BackupFileExportPicker")
        // iOS 27's initial folder shows Back/Save rather than a Cancel button.
        // Exercise the system sheet's interactive cancellation once.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
        let exportButton = app.buttons["exportLibraryBackup"]
        let restored = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: exportButton)
        wait(for: [restored], timeout: 15)
        app.buttons["restoreLibraryBackup"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Browse View (Picker)"].firstMatch.waitForExistence(timeout: 15))
        screenshot(app, name: "BackupFileImportPicker")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
        let importDismissed = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: exportButton)
        wait(for: [importDismissed], timeout: 15)
        XCTAssertFalse(app.descendants(matching: .any)["storageError"].firstMatch.exists)
        app.terminate()
        app.launchEnvironment["INTERLINE_UI_DARK_APPEARANCE"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["libraryMenu"].tap()
        XCTAssertTrue(app.buttons["最近阅读"].waitForExistence(timeout: 10))
        let dataAction = app.buttons["数据与存储"]
        screenshot(app, name: "LibraryMenuDarkLargeText")
        for _ in 0..<4 {
            if dataAction.exists && dataAction.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(dataAction.waitForExistence(timeout: 10))
        dataAction.tap()
        XCTAssertTrue(app.buttons["exportLibraryBackup"].waitForExistence(timeout: 10))
        let help = app.staticTexts["backupFormatHelp"]
        // Form creates offscreen cells lazily at accessibility sizes.
        for _ in 0..<6 {
            if help.exists && help.isHittable { break }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(help.exists)
        XCTAssertTrue(help.isHittable)
        screenshot(app, name: "BackupHelpDarkLargeText")
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        wait(for: [landscape], timeout: 10)
        for _ in 0..<3 where !help.isHittable { app.swipeUp() }
        XCTAssertTrue(help.isHittable)
        screenshot(app, name: "BackupHelpDarkLargeLandscape")
    }

    func testDetailMetadataFailureRetainsInputAndRetry() {
        let app = launch(blockCatalog: true)
        let details = app.buttons["星河织梦录的书籍详情"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        let title = app.textFields["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        let old = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "未保存的新书名")
        let save = app.buttons["saveBookMetadata"]
        for _ in 0..<5 {
            if save.exists && save.isHittable { break }
            app.swipeUp()
        }
        save.tap()
        XCTAssertTrue(app.staticTexts["pageOperationError"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["书籍详情"].exists)
        screenshot(app, name: "DetailMetadataFailure")
        app.buttons["retryPageOperation"].tap()
        XCTAssertTrue(app.staticTexts["pageOperationError"].exists)
        app.buttons["dismissPageOperationError"].tap()
        for _ in 0..<5 {
            if title.exists && title.isHittable { break }
            app.swipeDown()
        }
        XCTAssertEqual(title.value as? String, "未保存的新书名")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["星河织梦录的书籍详情"].waitForExistence(timeout: 10))
    }

    func testDetailRemovalFailureKeepsPageAndBook() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(blockCatalog: true, largeDark: true)
        let details = app.buttons["星河织梦录的书籍详情"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.tap()
        let remove = app.buttons["removeBookFromDetail"]
        for _ in 0..<10 {
            if remove.exists && remove.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(remove.exists)
        remove.tap()
        XCTAssertTrue(app.staticTexts["pageOperationError"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["书籍详情"].exists)
        screenshot(app, name: "DetailRemovalFailureDarkLarge")
        XCTAssertTrue(app.buttons["retryPageOperation"].isHittable)
        XCTAssertTrue(app.buttons["dismissPageOperationError"].isHittable)
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        wait(for: [rotated], timeout: 10)
        XCTAssertTrue(app.buttons["retryPageOperation"].isHittable)
        XCTAssertTrue(app.buttons["dismissPageOperationError"].isHittable)
        screenshot(app, name: "DetailRemovalFailureDarkLargeLandscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["星河织梦录的书籍详情"].waitForExistence(timeout: 10))
    }

    func testReadingSurvivesBackgroundAndForeground() {
        let app = launch()
        app.buttons["continueReading"].tap()
        let canvas = readyCanvas(app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let text = canvas.label
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(readyCanvas(app).label, text)
    }


    func testAccessibilityLabelsAndTraitsOnShelfAndReader() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["continueReading"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        app.buttons["continueReading"].tap()
        let canvas = readyCanvas(app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["readerTOC"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }

}
