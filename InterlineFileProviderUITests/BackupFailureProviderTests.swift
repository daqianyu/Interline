import XCTest

@MainActor
final class BackupFailureProviderTests: XCTestCase {
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
        let local = app.cells["DOC.sidebar.item.On My iPhone"]
        let container = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "Interline,")).firstMatch
        let ready = expectation(for: NSPredicate { _, _ in folder.exists || title.exists || local.exists || container.exists }, evaluatedWith: app)
        wait(for: [ready], timeout: 40)
        // Recorded first legacy selection opens On My iPhone, one level above
        // Interline. Enter each observed level rather than trusting the hint.
        if local.exists {
            tapSettled(local)
            XCTAssertTrue(container.waitForExistence(timeout: 20), app.debugDescription)
        }
        if container.exists {
            tapSettled(container)
            XCTAssertTrue(folder.waitForExistence(timeout: 20), app.debugDescription)
        }
        if folder.exists { tapSettled(folder) }
        else { XCTAssertTrue(title.exists, app.debugDescription) }
    }

    private func evidence(_ app: XCUIApplication, event: String) {
        let text = app.staticTexts["fp06Evidence"]
        let value = event + "|unchanged=true|workspaces=0"
        let ready = expectation(for: NSPredicate(format: "exists == true AND label == %@", value), evaluatedWith: text)
        wait(for: [ready], timeout: 20)
    }

    private func select(_ app: XCUIApplication, suite: String, stem: String, retry: Bool) {
        tapSettled(app.buttons[retry ? "retryPageOperation" : "restoreLibraryBackup"])
        XCTAssertTrue(app.descendants(matching: .any)["Browse View (Picker)"].firstMatch.waitForExistence(timeout: 40))
        providerFolder(app, suite: suite)
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", stem)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 20), app.debugDescription)
        capture("FP06Select-" + stem)
        tapSettled(file)
    }

    func testCorruptFilesAndCancelledPreparationPreserveExistingLibrary() {
        let provider = UUID().uuidString
        let app = launch(library: UUID().uuidString, provider: provider, role: "failure-provider")
        XCTAssertTrue(app.buttons["continueReading"].label.contains("FP05 Backup Source"))
        storage(app)
        evidence(app, event: "initial")
        let files = ["FP06-truncated.interlinebackup", "FP06-badhash.interlinebackup", "FP06-badquote.json"]
        for (index, name) in files.enumerated() {
            select(app, suite: provider, stem: (name as NSString).deletingPathExtension, retry: index > 0)
            let error = app.staticTexts["pageOperationError"]
            XCTAssertTrue(error.waitForExistence(timeout: 30), app.debugDescription)
            XCTAssertTrue(error.label.contains("备份读取"), error.label)
            XCTAssertTrue(app.buttons["retryPageOperation"].isHittable)
            XCTAssertFalse(app.buttons["合并恢复"].exists)
            evidence(app, event: "rejected:" + name)
            capture("FP06Rejected-" + name)
        }
        // Use the real error retry action to select a valid file. A successful
        // preparation must own a workspace; the host report checks that event.
        select(app, suite: provider, stem: "FP06-valid", retry: true)
        XCTAssertTrue(app.buttons["合并恢复"].waitForExistence(timeout: 30))
        capture("FP06ValidConfirmation")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        let cancelled = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["合并恢复"])
        wait(for: [cancelled], timeout: 15)
        evidence(app, event: "cancelled")
        XCTAssertFalse(app.staticTexts["pageOperationError"].exists)
        capture("FP06CancelledAndClean")
        tapSettled(app.buttons["完成"])
        XCTAssertTrue(app.buttons["continueReading"].label.contains("第二章 归途"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["continueReading"].waitForExistence(timeout: 20))
        storage(app)
        evidence(app, event: "initial")
        capture("FP06RelaunchedUnchanged")
        tapSettled(app.buttons["完成"])
        tapSettled(app.buttons["continueReading"])
        let canvas = app.descendants(matching: .any)["readerCanvas"].firstMatch
        let body = expectation(for: NSPredicate(format: "exists == true AND label CONTAINS %@ AND label CONTAINS %@", "第二章 归途", "取消和失败后，原书、笔记和草稿仍应保留。"), evaluatedWith: canvas)
        wait(for: [body], timeout: 20)
        capture("FP06RetainedSecondChapter")
        app.terminate()
    }
}
