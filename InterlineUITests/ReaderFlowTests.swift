import XCTest

@MainActor
final class ReaderFlowTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["INTERLINE_UI_TESTING"] = "1"
        app.launch()
        return app
    }

    private func screenshot(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
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

}
