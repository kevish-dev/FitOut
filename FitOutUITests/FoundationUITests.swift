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
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Edit profile"].tap()
        XCTAssertTrue(app.navigationBars["Edit profile"].waitForExistence(timeout: 3))
    }

    @MainActor func testRoutineTemplateCreationAndEditing() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-shell"]
        app.launch()
        if app.buttons["dismissHealthExplainer"].waitForExistence(timeout: 10) { app.buttons["dismissHealthExplainer"].tap() }
        app.tabBars.buttons["Gym"].tap()
        app.buttons["newRoutine"].tap()
        app.buttons["Full Body"].tap()
        XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 3))
        app.buttons["saveRoutine"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Full Body")).firstMatch.waitForExistence(timeout: 3))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Full Body")).firstMatch.tap()
        XCTAssertTrue(app.textFields["routineName"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        app.buttons["Exercise library"].tap()
        XCTAssertTrue(app.navigationBars["Exercise library"].waitForExistence(timeout: 3))
        app.buttons["Filter by muscle"].tap()
        XCTAssertTrue(app.navigationBars["Muscle map"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["muscle-chest"].waitForExistence(timeout: 5))
        app.buttons["muscle-chest"].tap()
        XCTAssertTrue(app.staticTexts["selectedMuscles"].label.contains("Chest"))
        app.buttons["Back"].tap()
        app.buttons["Done"].tap()
    }

    @MainActor func testWorkoutSetSurvivesTerminationAndFinishes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Gym"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Gym"].tap()
        app.buttons["startQuickWorkout"].tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5))
        app.buttons["workoutAddExercise"].tap()
        app.buttons["Bench press"].tap()
        app.buttons["completeSet"].firstMatch.tap()
        let saved = NSPredicate(format: "label CONTAINS %@", "completed")
        expectation(for: saved, evaluatedWith: app.buttons["completeSet"].firstMatch)
        waitForExpectations(timeout: 5)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Gym"].tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5) || app.buttons["resumeWorkout"].exists)
        if !app.navigationBars["Workout"].exists { app.buttons["resumeWorkout"].tap() }
        XCTAssertTrue(app.buttons["completeSet"].firstMatch.label.contains("completed"))
        app.swipeUp()
        app.buttons["finishWorkout"].tap()
        app.buttons["Complete workout"].tap()
        XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
    }

}
