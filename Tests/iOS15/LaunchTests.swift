import XCTest

final class IOS15LaunchTests: XCTestCase {
    func testActualAppLaunchWithoutActivityKit() {
        XCTAssertEqual(ProcessInfo.processInfo.operatingSystemVersion.majorVersion, 15)
        let app = XCUIApplication(bundleIdentifier: "com.dm2mymcszt.trollroute")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), app.debugDescription)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "actual-app-ios15-launch"; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "actual-app-ios15-hierarchy"; tree.lifetime = .keepAlways; add(tree)
    }
}
