import XCTest

/// Captures App Store screenshots by driving the app (seeded with demo data
/// via the UITEST_SCREENSHOTS launch argument) and attaching a full-screen
/// image at each stop. The screenshots workflow exports these attachments.
final class ScreenshotTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testCaptureScreenshots() {
        let app = XCUIApplication()
        app.launchArguments += ["UITEST_SCREENSHOTS"]
        app.launch()

        // 1) Receipt tab (the default) showing a scanned, itemized bill.
        XCTAssertTrue(app.tabBars.buttons["Trips"].waitForExistence(timeout: 20))
        capture("01-receipt")

        // 2) Trips list.
        app.tabBars.buttons["Trips"].tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10))
        capture("02-trips")

        // 3) A trip's expenses.
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["Balances"].waitForExistence(timeout: 10))
        capture("03-expenses")

        // 4) Balances and the minimized settle-up.
        app.buttons["Balances"].tap()
        capture("04-settle-up")
    }

    private func capture(_ name: String) {
        // Let SwiftUI finish any transition before grabbing the frame.
        Thread.sleep(forTimeInterval: 0.6)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
