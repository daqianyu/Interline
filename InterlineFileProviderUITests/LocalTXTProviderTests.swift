import XCTest

@MainActor
final class LocalTXTProviderTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let suite = UUID().uuidString
        app.launchEnvironment["INTERLINE_UI_TESTING"] = "1"
        app.launchEnvironment["INTERLINE_UI_TEST_SUITE"] = suite
        app.launchEnvironment["INTERLINE_UI_PROVIDER_SUITE"] = suite
        app.launch()
        XCTAssertTrue(app.staticTexts["书架是空的"].waitForExistence(timeout: 15))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openPicker(_ app: XCUIApplication) {
        app.buttons["importBook"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Browse View (Picker)"].firstMatch.waitForExistence(timeout: 40), app.debugDescription)
    }

    private func select(_ name: String, in app: XCUIApplication) {
        openPicker(app)
        // The default directory is a system hint: the first run actually opened
        // Documents instead. Navigate the observed provider hierarchy explicitly.
        let suite = app.launchEnvironment["INTERLINE_UI_PROVIDER_SUITE"]!
        let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "InterlineQ01-" + suite)).firstMatch
        let fixture = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "q01-utf8")).firstMatch
        let ready = expectation(for: NSPredicate { _, _ in folder.exists || fixture.exists }, evaluatedWith: app)
        wait(for: [ready], timeout: 30)
        if folder.exists {
            folder.tap()
        } else {
            // A previous selection may be remembered. Check its folder identity
            // before using a fixture, so every test reads its own source files.
            let title = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "InterlineQ01-" + suite)).firstMatch
            if !title.exists {
                app.buttons["DOC.navBarButton.backInHistory"].tap()
                XCTAssertTrue(folder.waitForExistence(timeout: 15), app.debugDescription)
                folder.tap()
            }
        }
        // Files may hide the extension. Match the unique fixture stem, not position.
        let cell = app.cells.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 15), app.debugDescription)
        capture("Provider-" + name)
        cell.tap()
    }

    private func importAndRead(_ name: String, encoding: String, duplicate: Bool = false) {
        let app = launch()
        select(name, in: app)
        let field = app.textFields["importTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), app.debugDescription)
        capture("Preview-" + name)
        let encodingRow = app.descendants(matching: .any)["importEncoding"].firstMatch
        XCTAssertTrue((encodingRow.label + " " + (encodingRow.value as? String ?? "")).contains(encoding), app.debugDescription)
        XCTAssertTrue(app.staticTexts["第一章 起点"].exists)
        XCTAssertTrue(app.staticTexts["第二章 归途"].exists)
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Q01 " + name)
        app.buttons["confirmImport"].tap()
        XCTAssertTrue(app.buttons["continueReading"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        let resume = app.buttons["continueReading"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCTAssertTrue(resume.label.contains("Q01 " + name))
        if duplicate {
            select("q01-duplicate", in: app)
            XCTAssertTrue(app.staticTexts["相同正文已经在书架中，不会重复添加。"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["confirmImport"].isEnabled)
            capture("DuplicateRejected")
            app.buttons["取消"].tap()
            XCTAssertTrue(resume.label.contains("Q01 " + name))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'bookCover-'" )).count, 1)
        }
        resume.tap()
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        let body = expectation(for: NSPredicate(format: "label CONTAINS %@", "这是文件流程验收专用的原创测试文字"), evaluatedWith: canvas)
        wait(for: [body], timeout: 15)
        capture("ReadAfterRelaunch-" + name)
    }

    func testUTF8AndDuplicate() { importAndRead("q01-utf8", encoding: "UTF-8", duplicate: true) }
    func testUTF16LE() { importAndRead("q01-utf16le", encoding: "UTF-16 LE") }
    func testUTF16BE() { importAndRead("q01-utf16be", encoding: "UTF-16 BE") }
    func testGB18030() { importAndRead("q01-gb18030", encoding: "GB18030 / GBK") }

    func testCancelEmptyAndOversizedDoNotImport() {
        let app = launch()
        openPicker(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
        XCTAssertTrue(app.staticTexts["书架是空的"].waitForExistence(timeout: 10))
        let returned = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: app.buttons["importBook"].firstMatch)
        wait(for: [returned], timeout: 15)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("CancelledTXTSelection")
        select("q01-empty", in: app)
        XCTAssertTrue(app.staticTexts["文件没有可阅读的正文"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["confirmImport"].isEnabled)
        capture("Rejected-q01-empty")
        app.buttons["取消"].tap()
        select("q01-over-20mib", in: app)
        XCTAssertTrue(app.alerts["导入失败"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["文件读取未完成：文件超过 20 MB，请先拆分后再导入"].exists)
        capture("Rejected-q01-over-20mib")
        app.alerts.buttons["好"].tap()
        XCTAssertTrue(app.staticTexts["书架是空的"].exists)
        XCTAssertFalse(app.buttons["continueReading"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["书架是空的"].waitForExistence(timeout: 15))
    }
}
