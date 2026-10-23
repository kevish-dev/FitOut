import XCTest

final class FoundationUITests: XCTestCase {
    @MainActor func testTabsAndSettingsWithoutIntegrations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-shell"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        if app.buttons["dismissHealthExplainer"].waitForExistence(timeout: 3) { app.buttons["dismissHealthExplainer"].tap() }
        for title in ["Gym", "Nutrition", "Health", "AI Coach", "Home"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3))
        }
        app.buttons["Open Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UITest")).firstMatch.exists)
    }
    @MainActor func testOnboardingCompletionAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-profile", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["getStartedButton"].waitForExistence(timeout: 10))
        app.buttons["getStartedButton"].tap()
        app.buttons["Build muscle"].tap()
        app.buttons["profileContinue"].tap()
        app.textFields["profileName"].tap()
        app.textFields["profileName"].typeText("Test User\n")
        app.swipeUp()
        app.buttons["completeProfile"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        if app.buttons["dismissHealthExplainer"].waitForExistence(timeout: 3) { app.buttons["dismissHealthExplainer"].tap() }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        app.buttons["Open Settings"].tap()
        app.buttons["Edit profile"].tap()
        XCTAssertTrue(app.navigationBars["Edit profile"].waitForExistence(timeout: 3))
    }

}
