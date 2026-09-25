import XCTest

final class LiveActivitySystemTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }
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
        let hierarchy = XCTAttachment(string: board.debugDescription)
        hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func goHome() {
        XCUIDevice.shared.press(.home)
        let icon = board.icons["Activity QA"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10), board.debugDescription)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: icon)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 10), .completed)
    }
    private func expand() {
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.035)).press(forDuration: 1.2)
    }
    private func waitForPresentation(_ identifiers: [String]) {
        var previous: [CGRect] = []
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let elements = identifiers.map { board.descendants(matching: .any).matching(identifier: $0).firstMatch }
            guard elements.allSatisfy({ $0.exists && !$0.frame.isEmpty }) else { return false }
            let frames = elements.map(\.frame)
            defer { previous = frames }
            return frames == previous
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, board.debugDescription)
    }
    func testDynamicIslandControls() throws {
        let app = try app()
        defer { app.terminate() }
        app.buttons["Start real"].tap()
        XCTAssertTrue(app.staticTexts["QA moving"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10), app.debugDescription)
        goHome()
        waitForPresentation(["route-activity-compact-progress", "route-activity-compact-time"])
        capture("system-compact")
        expand()
        XCTAssertTrue(board.buttons["Pause"].waitForExistence(timeout: 10), board.debugDescription)
        capture("system-expanded")
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
        goHome(); expand()
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
        app.buttons["Seek 46"].tap()
        let companion = XCUIApplication(bundleIdentifier: "local.trollroute.companionqa")
        companion.launch()
        companion.buttons["Start companion"].tap()
        XCTAssertTrue(companion.staticTexts["Companion ready"].waitForExistence(timeout: 10))
        goHome()
        waitForPresentation(["route-activity-minimal-progress", "qa-companion-minimal"])
        capture("system-minimal-two-activities")
        companion.activate()
        companion.buttons["End companion"].tap()
        XCTAssertTrue(companion.staticTexts["Companion ended"].waitForExistence(timeout: 10))
        companion.terminate()
        app.activate()
        goHome()
        // Test-driver capability only; never shipped in the app/widget.
        let selector = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: selector) else {
            XCTFail("Test driver cannot press Lock; actual Lock Screen evidence is still required")
            return
        }
        XCUIDevice.shared.perform(selector)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(board.staticTexts["Test destination"].waitForExistence(timeout: 10), board.debugDescription)
        if board.buttons["Allow"].exists { board.buttons["Allow"].tap() }
        capture("system-lock-screen")
    }

    func testNotificationCentreControls() throws {
        let app = try app()
        defer { app.terminate() }
        app.buttons["Start real"].tap()
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10))
        goHome()
        // Notification Centre on an authenticated device, the reported surface.
        // A passcode-locked device requires authentication before iOS runs buttons.
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.01))
            .press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)))
        XCTAssertTrue(board.staticTexts["Test destination"].waitForExistence(timeout: 10), board.debugDescription)
        XCTAssertTrue(board.staticTexts["20 km/h"].exists, board.debugDescription)
        capture("notification-centre-moving")
        XCTAssertTrue(board.buttons["Pause"].exists)
        board.buttons["Pause"].tap()
        XCTAssertTrue(board.buttons["Resume"].waitForExistence(timeout: 10), board.debugDescription)
        capture("notification-centre-paused")
        board.buttons["Resume"].tap()
        XCTAssertTrue(board.buttons["Pause"].waitForExistence(timeout: 10))
        board.buttons["Stop"].tap()
        XCTAssertTrue(board.buttons["Restore real location"].waitForExistence(timeout: 10))
        capture("notification-centre-stop-choices")
        board.buttons["Cancel"].tap()
        XCTAssertTrue(board.buttons["Pause"].waitForExistence(timeout: 10))
        board.buttons["Stop"].tap()
        XCTAssertTrue(board.buttons["Restore real location"].waitForExistence(timeout: 10))
        board.buttons["Restore real location"].tap()
        app.activate()
        XCTAssertTrue(app.staticTexts["QA stopped"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["QA no activity"].waitForExistence(timeout: 10))
    }

    func testSpecificPlaceOpensPickerAndAppliesFavorite() throws {
        let app = try app()
        defer { app.terminate() }
        app.buttons["Start real"].tap()
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10))
        goHome(); expand()
        XCTAssertTrue(board.buttons["Stop"].waitForExistence(timeout: 10))
        board.buttons["Stop"].tap()
        XCTAssertTrue(board.buttons["Go to a specific location"].waitForExistence(timeout: 10))
        board.buttons["Go to a specific location"].tap()
        // Do not activate the app from the test: the production Link must do it.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.navigationBars["After stopping"].waitForExistence(timeout: 10), app.debugDescription)
        capture("specific-place-picker")
        let favorite = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Activity test favorite")).firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 10), app.debugDescription)
        favorite.tap()
        XCTAssertTrue(app.staticTexts["QA stopped"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["QA at favorite"].exists)
        XCTAssertTrue(app.staticTexts["QA no activity"].waitForExistence(timeout: 10))
    }

    func testSpeedSeekReturnAndToggleDoNotStopRoute() throws {
        let app = try app()
        defer { app.terminate() }
        app.buttons["Start real"].tap()
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10))
        app.buttons["Seek 46"].tap()
        app.buttons["Speed 120"].tap()
        goHome(); expand()
        XCTAssertTrue(board.staticTexts["120 km/h"].waitForExistence(timeout: 10), board.debugDescription)
        capture("system-speed-seek")
        app.activate()
        app.buttons["Return leg"].tap()
        goHome(); expand()
        XCTAssertTrue(board.staticTexts["Original start"].waitForExistence(timeout: 10), board.debugDescription)
        capture("system-return-destination")
        app.activate()
        app.buttons["Disable activity"].tap()
        XCTAssertTrue(app.staticTexts["QA no activity"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["QA moving"].exists)
        app.buttons["Enable activity"].tap()
        XCTAssertTrue(app.staticTexts["QA activity ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["QA moving"].exists)
    }
}
