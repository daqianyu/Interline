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

    private func launch(failNoteSave: Bool = false, failDraftSave: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["INTERLINE_UI_TESTING"] = "1"
        app.launchEnvironment["INTERLINE_UI_TEST_SUITE"] = UUID().uuidString
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
        wait(for: [dismissed], timeout: 5)
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
