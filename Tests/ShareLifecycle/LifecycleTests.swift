import XCTest
import CoreLocation

final class ShareLifecycleTests: XCTestCase {
    private func fixture() throws -> (XCUIApplication, URL, SharedPlaceInbox) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShareLifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = XCUIApplication(bundleIdentifier: "local.trollroute.sharelifecycle")
        app.launchEnvironment["TROLLROUTE_QA_ROOT"] = root.path
        return (app, root, SharedPlaceInbox(container: root))
    }
    private func request(_ name: String, _ action: SharedPlaceAction) -> SharedPlaceRequest {
        var place = RoutePlace(name: name, address: "Shared address",
            coordinate: CLLocationCoordinate2D(latitude: 44.8378, longitude: -0.5792))
        place.sharedSource = .googleMaps
        return SharedPlaceRequest(place: place, action: action)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func expectEndpoint(_ app: XCUIApplication, _ request: SharedPlaceRequest) {
        XCTAssertTrue(app.navigationBars["TrollRoute Navigation"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[request.name].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["From Google Maps"].firstMatch.exists)
        XCTAssertFalse(app.navigationBars["From Google Maps"].exists, "No second confirmation screen")
    }
    private func latency(_ root: URL, _ request: SharedPlaceRequest) throws -> Double {
        let text = try String(contentsOf: root.appendingPathComponent("accepted-" + request.id.uuidString), encoding: .utf8)
        return try XCTUnwrap(Double(text))
    }

    func testActiveSignalDismissesPickerAndAppliesBothEndpoints() throws {
        let (app, root, inbox) = try fixture()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.launch()
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 10))
        app.buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Find a place"].waitForExistence(timeout: 5))
        let start = request("Shared route start", .start)
        try inbox.enqueue(start) // UI-test runner is a separate process.
        expectEndpoint(app, start)
        XCTAssertLessThan(try latency(root, start), 1.0, "Active app must consume the signal within one second")
        capture(app, "active-shared-start")
        let destination = request("Shared destination", .destination)
        try inbox.enqueue(destination)
        XCTAssertTrue(app.staticTexts[destination.name].waitForExistence(timeout: 10))
        expectEndpoint(app, destination)
        XCTAssertTrue(app.staticTexts[start.name].exists, "Later share preserves the other endpoint")
        XCTAssertLessThan(try latency(root, destination), 1.0)
        XCTAssertTrue(try inbox.pendingRequests().isEmpty)
        capture(app, "active-shared-destination")
    }

    func testBackgroundRequestIsPresentedOnActivation() throws {
        let (app, root, inbox) = try fixture()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.launch()
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let backgrounded = expectation(for: NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }, evaluatedWith: app)
        wait(for: [backgrounded], timeout: 5)
        let destination = request("Background destination", .destination)
        try inbox.enqueue(destination)
        app.activate()
        expectEndpoint(app, destination)
        XCTAssertTrue(try inbox.pendingRequests().isEmpty)
        capture(app, "background-share-on-activation")
    }

    func testColdLaunchConsumesOnceAndDoesNotReplay() throws {
        let (app, root, inbox) = try fixture()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.terminate()
        let start = request("Cold launch start", .start)
        try inbox.enqueue(start)
        app.launch()
        expectEndpoint(app, start)
        XCTAssertTrue(try inbox.pendingRequests().isEmpty)
        capture(app, "cold-launch-shared-start")
        app.terminate()
        try inbox.enqueue(start)
        XCTAssertTrue(try inbox.pendingRequests().isEmpty, "Same UUID must not replay after a restart")
        app.launch()
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["TrollRoute Navigation"].exists)
        XCTAssertNil(try inbox.routeDraft().presentation)
    }

    func testEditedFavoriteSavesWithoutOpeningApp() throws {
        let (app, root, _) = try fixture()
        defer { app.terminate(); try? FileManager.default.removeItem(at: root) }
        app.launchArguments = ["--share"]
        app.launch()
        let field = app.textFields["Place name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Shared landmark".count) + "My saved place")
        app.buttons["Save as favorite"].tap()
        XCTAssertTrue(app.staticTexts["Saved to Favorites"].waitForExistence(timeout: 5))
        let saved = try FavoritesStore(url: root.appendingPathComponent("favorites.json")).read()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.name, "My saved place")
        XCTAssertEqual(saved.first?.latitude ?? 0, 44.8378, accuracy: 0.00001)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("opened").path))
        capture(app, "share-favorite-saved")
    }
}
