import XCTest

final class LiveActivitySystemTests: XCTestCase {
    private let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private func app() throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "local.trollroute.activityqa")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Activity-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        app.launchEnvironment["TROLLROUTE_QA_ROOT"] = folder.path
        app.launch()
        XCTAssertTrue(app.buttons["Start real"].waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let hierarchy = XCTAttachment(string: board.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    private func expand() {
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
    }
    func testDynamicIslandControls() throws {
        let app = try app()
        defer { app.terminate() }
        app.buttons["Start real"].tap()
        XCTAssertTrue(app.staticTexts["QA moving"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10), app.debugDescription)
        XCUIDevice.shared.press(.home)
        capture("system-compact")
        expand()
        capture("system-expanded")
        XCTAssertTrue(board.buttons["Pause"].waitForExistence(timeout: 10), board.debugDescription)
        board.buttons["Pause"].tap()
        XCTAssertTrue(board.buttons["Resume"].waitForExistence(timeout: 10), board.debugDescription)
        capture("system-paused")
        board.buttons["Resume"].tap()
        XCTAssertTrue(board.buttons["Pause"].waitForExistence(timeout: 10))
        board.buttons["Stop"].tap()
        XCTAssertTrue(board.buttons["Stay at current location"].waitForExistence(timeout: 10), board.debugDescription)
        for title in ["Return to route start", "Go to a specific location", "Restore real location", "Cancel"] {
            XCTAssertTrue(board.buttons[title].exists, board.debugDescription)
        }
        capture("system-stop-real")
        board.buttons["Cancel"].tap()
        XCTAssertTrue(board.buttons["Pause"].waitForExistence(timeout: 10))
        board.buttons["Stop"].tap()
        XCTAssertTrue(board.buttons["Restore real location"].waitForExistence(timeout: 10))
        board.buttons["Restore real location"].tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["QA stopped"].waitForExistence(timeout: 10))
        app.buttons["Start spoof"].tap()
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10), app.debugDescription)
        XCUIDevice.shared.press(.home); expand()
        XCTAssertTrue(board.buttons["Stop"].waitForExistence(timeout: 10))
        board.buttons["Stop"].tap()
        XCTAssertTrue(board.buttons["Return to previous spoofed location"].waitForExistence(timeout: 10))
        capture("system-stop-previous")
        board.buttons["Return to previous spoofed location"].tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["QA stopped"].waitForExistence(timeout: 10))
    }
    func testMinimalAndLockScreen() throws {
        let app = try app()
        defer { app.terminate() }
        app.buttons["Start real"].tap()
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Companion"].tap()
        XCUIDevice.shared.press(.home)
        capture("system-minimal-two-activities")
        // Test-driver capability only; never shipped in the app/widget.
        let selector = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: selector) else {
            XCTFail("Test driver cannot press Lock; actual Lock Screen evidence is still required")
            return
        }
        XCUIDevice.shared.perform(selector)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(board.staticTexts["Test destination"].waitForExistence(timeout: 10), board.debugDescription)
        capture("system-lock-screen")
    }
}
