import XCTest

final class MapGestureTests: XCTestCase {
    func testLocationOverviewExplainsSystemRegistrationAndDeniedAccess() {
        let app = XCUIApplication(bundleIdentifier: "local.trollroute.workspacepreview")
        app.launchArguments = ["--screen", "access-good"]
        app.launch()
        XCTAssertTrue(app.staticTexts["While Using the App"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["System"].exists)
        XCTAssertTrue(app.staticTexts["On"].exists)
        app.buttons["access-TrollStore registration"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "System registration is normal")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "system-registration-explanation")
        app.terminate()
        app.launchArguments = ["--screen", "access-bad"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Never"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Unavailable"].exists)
        app.buttons["access-Location access"].tap()
        XCTAssertTrue(app.buttons["Open iOS Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Allow location access"].exists, "Denied permission requires Settings, not another system prompt")
        capture(app, "denied-location-explanation")
        app.terminate()
    }

    private func launch(_ screen: String = "gestures", labels: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "local.trollroute.workspacepreview")
        app.launchArguments = ["--screen", screen, "--labels", labels ? "yes" : "no"]
        app.launch()
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 15))
        let ready = NSPredicate { _, _ in self.mapState(app).count == 4 }
        expectation(for: ready, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMainStopPreservesRouteUntilConfirmed() {
        let app = launch()
        app.buttons["Route"].tap()
        app.buttons["Stop"].tap()
        let alert = app.alerts["Stop location spoofing?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["This will stop the running route and restore your real location."].exists)
        capture(app, "main-stop-running-route")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["toolbar-state"].label.contains("running=true"))
        app.buttons["Stop"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Stop"].tap()
        XCTAssertTrue(app.staticTexts["toolbar-state"].label.contains("running=false"))
        app.terminate()
        app.launchArguments = ["--screen", "gestures", "--stop-without-confirmation"]
        app.launch()
        XCTAssertTrue(app.buttons["Route"].waitForExistence(timeout: 15))
        app.buttons["Route"].tap()
        app.buttons["Stop"].tap()
        XCTAssertFalse(alert.exists)
        XCTAssertTrue(app.staticTexts["toolbar-state"].label.contains("running=false"))
    }

    func testLongPressConfirmationCancelAndCreate() {
        let app = launch("gestures-confirm")
        let spot = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.65))
        let alert = app.alerts["Create route to here?"]
        for iteration in 0..<5 {
            spot.press(forDuration: 1)
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            if iteration == 0 { capture(app, "long-press-confirmation") }
            alert.buttons["Cancel"].tap()
            XCTAssertEqual(app.staticTexts["gesture-counts"].label, "presses=\(iteration),taps=0")
            spot.press(forDuration: 1)
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            alert.buttons["Create route"].tap()
            XCTAssertEqual(app.staticTexts["gesture-counts"].label, "presses=\(iteration + 1),taps=0")
        }
    }

    private func mapState(_ app: XCUIApplication) -> [Double] {
        let probe = app.staticTexts["map-observation"]
        guard probe.exists else { return [] }
        return (probe.value as? String ?? "").split(separator: ",").compactMap { Double($0) }
    }

    func testDragBelowStopPansMapWithoutMovingToolbar() {
        for labels in [true, false] {
            let app = launch(labels: labels)
            let stop = app.buttons["Stop"]
            XCTAssertTrue(stop.isHittable)
            let stopBefore = stop.frame
            let before = mapState(app)
            XCTAssertEqual(before.count, 4)
            guard before.count == 4 else { return }
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: stopBefore.midX, dy: stopBefore.maxY + 140))
            let end = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: stopBefore.midX, dy: stopBefore.maxY + 60))
            start.press(forDuration: 0.05, thenDragTo: end)
            let moved = NSPredicate { _, _ in
                let after = self.mapState(app)
                return after.count == 4 && abs(after[0] - before[0]) + abs(after[1] - before[1]) > 0.0001
            }
            expectation(for: moved, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            XCTAssertEqual(stop.frame.minY, stopBefore.minY, accuracy: 1)
            XCTAssertEqual(stop.frame.minX, stopBefore.minX, accuracy: 1)
            let toolbar = app.scrollViews["map-toolbar"]
            XCTAssertLessThan(toolbar.frame.maxY, start.screenPoint.y)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = labels ? "toolbar-labels-after-map-pan" : "toolbar-icons-after-map-pan"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    func testShortWorkspaceKeepsStopReachableByScrolling() {
        let app = launch("gestures-short")
        let toolbar = app.scrollViews["map-toolbar"]
        XCTAssertLessThanOrEqual(toolbar.frame.height, 240)
        toolbar.swipeUp()
        XCTAssertTrue(app.buttons["Stop"].isHittable)
        app.buttons["Stop"].tap()
        XCTAssertTrue(app.alerts["Stop location spoofing?"].waitForExistence(timeout: 3),
                      app.staticTexts["toolbar-state"].label)
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts["Stop location spoofing?"].exists)
    }

    func testLongPressSingleTapAndDoubleTapAreSeparate() {
        let app = launch("gestures-long")
        let spot = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.65))
        spot.press(forDuration: 1)
        XCTAssertEqual(app.staticTexts["gesture-counts"].label, "presses=1,taps=0")
        let before = mapState(app)
        XCTAssertEqual(before.count, 4)
        guard before.count == 4 else { return }
        spot.doubleTap()
        let zoomed = NSPredicate { _, _ in
            let after = self.mapState(app)
            return after.count == 4 && after[2] < before[2] * 0.9
        }
        expectation(for: zoomed, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["gesture-counts"].label, "presses=1,taps=0")
        spot.tap()
        let tapped = NSPredicate(format: "label == %@", "presses=1,taps=1")
        expectation(for: tapped, evaluatedWith: app.staticTexts["gesture-counts"])
        waitForExpectations(timeout: 5)
    }

    func testFreshDoubleTapZoomsWithoutSelectingLocation() {
        let app = launch("gestures-long")
        let before = mapState(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.65)).doubleTap()
        expectation(for: NSPredicate { _, _ in
            let after = self.mapState(app)
            return after.count == 4 && after[2] < before[2] * 0.9
        }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["gesture-counts"].label, "presses=0,taps=0")
    }

    func testPanWithRouteHoldEnabledDoesNotCreateRouteOrSelectLocation() {
        let app = launch("gestures-long")
        let before = mapState(app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
        expectation(for: NSPredicate { _, _ in
            let after = self.mapState(app)
            return before.count == 4 && after.count == 4
                && abs(after[0] - before[0]) + abs(after[1] - before[1]) > 0.0001
        }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["gesture-counts"].label, "presses=0,taps=0")
    }

    private func renameAndSave(_ app: XCUIApplication, to name: String) {
        let field = app.textFields["favorite-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let oldName = field.value as? String ?? ""
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count) + name)
        capture(app, name == "Saved search result" ? "favorite-from-search" : "favorite-from-map")
        app.navigationBars["Save as favorite"].buttons["Save"].tap()
    }

    func testSaveSearchAndMapPinWithoutSelectingLocation() {
        let app = XCUIApplication(bundleIdentifier: "local.trollroute.workspacepreview")
        app.launchArguments = ["--screen", "favorites"]
        app.launch()
        let star = app.buttons["Save Pasted location as favorite"]
        XCTAssertTrue(star.waitForExistence(timeout: 15))
        star.tap()
        renameAndSave(app, to: "Saved search result")
        XCTAssertTrue(app.navigationBars["Find a place"].waitForExistence(timeout: 5),
                      "Saving must leave the picker open, not select or move")
        app.navigationBars["Find a place"].buttons["Cancel"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Saved search result"),
                    evaluatedWith: app.staticTexts["saved-favorite"])
        waitForExpectations(timeout: 5)
        app.buttons["Search"].tap()
        app.buttons["Choose on Map"].tap()
        XCTAssertTrue(app.navigationBars["Choose on Map"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        app.buttons["Save as favorite"].tap()
        renameAndSave(app, to: "Saved map point")
        XCTAssertTrue(app.navigationBars["Choose on Map"].waitForExistence(timeout: 5),
                      "Saving a map pin must not select it")
        app.navigationBars["Choose on Map"].buttons["Cancel"].tap()
        app.navigationBars["Find a place"].buttons["Cancel"].tap()
        expectation(for: NSPredicate(format: "label == %@", "Saved map point"),
                    evaluatedWith: app.staticTexts["saved-favorite"])
        waitForExpectations(timeout: 5)
    }
}
