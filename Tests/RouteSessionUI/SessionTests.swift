import XCTest

final class RouteSessionTests: XCTestCase {
    private var activeApp: XCUIApplication?
    override func setUp() { super.setUp(); continueAfterFailure = false }
    override func tearDown() {
        if let app = activeApp {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "Previous scenario must finish before the next app launch")
        }
        activeApp = nil
        super.tearDown()
    }
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "local.trollroute.sessionui")
        activeApp = app
        app.launchArguments = arguments
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func waitState(_ app: XCUIApplication, _ text: String) {
        let state = app.staticTexts["session-state"]
        let expected = NSPredicate(format: "label CONTAINS %@", text)
        expectation(for: expected, evaluatedWith: state)
        waitForExpectations(timeout: 10)
    }
    private func scrollNavigation(_ app: XCUIApplication) {
        // The route preview is an interactive map. A centre-screen swipe pans
        // that map instead of scrolling once the preview reaches the centre.
        // Use the ScrollView's left margin, outside the map's padded frame.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.85))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)))
    }
    private func stop(_ app: XCUIApplication) {
        let button = app.buttons["Stop route"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["confirm-route-stop"].waitForExistence(timeout: 5))
    }
    func testPlaneAirportsAndPreview() {
        let app = launch(["--plane", "--navigation"])
        XCTAssertTrue(app.navigationBars["TrollRoute Navigation"].waitForExistence(timeout: 10))
        let departure = app.buttons["departure-airport"]
        for _ in 0..<8 { if departure.isHittable { break }; scrollNavigation(app) }
        XCTAssertTrue(app.buttons["Plane"].exists)
        XCTAssertTrue(departure.isHittable)
        capture(app, "plane-tab-and-airports")
        departure.tap()
        XCTAssertTrue(app.navigationBars["Departure airport"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("HND")
        let haneda = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "(HND)")).firstMatch
        XCTAssertTrue(haneda.waitForExistence(timeout: 5))
        capture(app, "plane-airport-selection")
        haneda.tap()
        let changed = app.buttons["departure-airport"]
        expectation(for: NSPredicate(format: "label CONTAINS %@", "HND"), evaluatedWith: changed)
        waitForExpectations(timeout: 10)
        let start = app.buttons["Start Route Simulation"]
        for _ in 0..<8 { if start.isHittable { break }; scrollNavigation(app) }
        XCTAssertTrue(start.isHittable)
        capture(app, "plane-flight-preview")
        waitState(app, "running=false")
    }
    func testHistoryReplayDeleteAndClear() {
        let app = launch(["--navigation", "--history"])
        XCTAssertTrue(app.buttons["route-history"].waitForExistence(timeout: 10))
        app.buttons["route-history"].tap()
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-entry-"))
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(entries.count, 2)
        capture(app, "history-with-entries-awaiting-approval")
        entries.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["TrollRoute Navigation"].waitForExistence(timeout: 5))
        waitState(app, "running=false")
        XCTAssertTrue(app.staticTexts["Saved walk"].exists)
        app.buttons["route-history"].tap()
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 5))
        entries.firstMatch.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertEqual(entries.count, 1)
        app.buttons["Clear history"].tap()
        XCTAssertTrue(app.alerts["Clear history?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertEqual(entries.count, 1)
        app.buttons["Clear history"].tap()
        app.alerts.buttons["Clear history"].tap()
        XCTAssertTrue(app.otherElements["history-empty"].exists || app.staticTexts["No routes yet"].waitForExistence(timeout: 5))
        XCTAssertEqual(entries.count, 0)
        capture(app, "history-empty-awaiting-approval")
    }
    func testPlanePlaybackAndLiveSpeed() {
        let app = launch(["--plane"])
        XCTAssertTrue(app.staticTexts["flight-live-speed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Cruise speed"].exists)
        capture(app, "plane-flight-in-progress")
        app.buttons["Pause route"].tap()
        waitState(app, "paused=true")
        XCTAssertEqual(app.staticTexts["flight-live-speed"].label, "Live speed: 0 km/h")
        app.buttons["Resume route"].tap()
        waitState(app, "paused=false")
        app.buttons["edit-route-finish"].tap()
        app.buttons["route-finish-action"].tap()
        XCTAssertTrue(app.buttons["Fly back to start"].waitForExistence(timeout: 5))
        app.buttons["Fly back to start"].tap()
        app.buttons["Done"].tap()
        waitState(app, "action=returnOnce")
        stop(app)
        app.buttons["route-stop-current"].tap()
        app.buttons["confirm-route-stop"].tap()
        waitState(app, "running=false")
        waitState(app, "active=true")
    }
    func testRealStartStopChoicesCancelAndConfirm() {
        let app = launch()
        stop(app)
        XCTAssertFalse(app.buttons["route-stop-previous"].exists)
        XCTAssertTrue(app.buttons["route-stop-specific"].exists)
        XCTAssertEqual(app.buttons["route-stop-current"].value as? String, "Selected")
        capture(app, "route-stop-real-start")
        app.buttons["Cancel"].tap()
        waitState(app, "running=true")
        stop(app)
        app.buttons["route-stop-current"].tap()
        app.buttons["confirm-route-stop"].tap()
        waitState(app, "running=false")
        waitState(app, "active=true")
        waitState(app, "stops=0")
    }
    func testPreviousStopAndExplicitReal() {
        let app = launch(["--previous"])
        stop(app)
        XCTAssertTrue(app.buttons["route-stop-previous"].exists)
        XCTAssertFalse(app.buttons["route-stop-specific"].exists)
        XCTAssertEqual(app.buttons["route-stop-previous"].value as? String, "Selected")
        capture(app, "route-stop-previous-spoof")
        app.buttons["route-stop-real"].tap()
        app.buttons["confirm-route-stop"].tap()
        waitState(app, "running=false")
        waitState(app, "active=false")
        XCTAssertFalse(app.alerts["Stop location spoofing?"].exists)
    }
    func testLiveFinishAndPanelCredits() {
        let app = launch()
        XCTAssertTrue(app.buttons["edit-route-finish"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "active-route-credit").count, 1)
        capture(app, "route-panel-finish-credit-expanded")
        app.buttons["edit-route-finish"].tap()
        XCTAssertTrue(app.buttons["route-finish-action"].waitForExistence(timeout: 5))
        app.buttons["route-finish-action"].tap()
        app.buttons["Drive back to start"].tap()
        capture(app, "live-finish-current-leg")
        app.buttons["Done"].tap()
        waitState(app, "action=returnOnce")
        waitState(app, "default=stay")
        app.buttons["Collapse route controls"].tap()
        XCTAssertTrue(app.buttons["Expand route controls"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "active-route-credit").count, 1)
        capture(app, "route-panel-credit-collapsed")
    }
    func testPreparedFinishInActualNavigation() {
        let app = launch(["--navigation"])
        XCTAssertTrue(app.navigationBars["TrollRoute Navigation"].waitForExistence(timeout: 10))
        let picker = app.buttons["route-finish-action"]
        for _ in 0..<8 {
            if picker.isHittable { break }
            scrollNavigation(app)
        }
        XCTAssertTrue(picker.isHittable)
        capture(app, "navigation-per-route-finish")
        picker.tap()
        app.buttons["Drive back to start"].tap()
        app.buttons["Close"].tap()
        waitState(app, "action=returnOnce")
        waitState(app, "default=stay")
    }
    func testBothNavigationStopControlsAsk() {
        let app = launch(["--active-navigation", "--previous"])
        XCTAssertTrue(app.buttons["navigation-toolbar-stop"].waitForExistence(timeout: 10))
        app.buttons["navigation-toolbar-stop"].tap()
        XCTAssertTrue(app.buttons["confirm-route-stop"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["navigation-status-stop"].waitForExistence(timeout: 5))
        app.buttons["navigation-status-stop"].tap()
        XCTAssertTrue(app.buttons["confirm-route-stop"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["route-stop-previous"].value as? String, "Selected")
        app.buttons["confirm-route-stop"].tap()
        app.buttons["Close"].tap()
        waitState(app, "running=false")
        waitState(app, "active=true")
        waitState(app, "stops=0")
    }
}
