import XCTest

final class FoundationUITests: XCTestCase {
    @MainActor private func navigate(_ destination: Int, in app: XCUIApplication) {
        app.buttons["navigationMenuButton"].tap()
        app.buttons["navigate-\(destination)"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    @MainActor func testNavigationAndSettingsWithoutIntegrations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-shell"]
        app.launch()
        XCTAssertTrue(app.buttons["navigationMenuButton"].waitForExistence(timeout: 10))
        if app.buttons["dismissHealthExplainer"].waitForExistence(timeout: 3) { app.buttons["dismissHealthExplainer"].tap() }
        for (destination, title) in [(1, "Gym"), (2, "Nutrition"), (3, "Health"), (4, "AI Coach"), (0, "Home")] {
            navigate(destination, in: app)
            if destination == 0 { XCTAssertTrue(app.staticTexts["Welcome!"].waitForExistence(timeout: 3)) }
            else if destination == 1 { XCTAssertTrue(app.staticTexts["gymTitle"].waitForExistence(timeout: 3)) }
            else if destination == 4 { XCTAssertTrue(app.staticTexts["coachTitle"].waitForExistence(timeout: 3)) }
            else { XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 3)) }
        }
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.buttons["Open Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UITest")).firstMatch.exists)
    }
    @MainActor func testCoachShowsHonestUnavailableState() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-shell"]
        app.launch()
        if app.buttons["dismissHealthExplainer"].waitForExistence(timeout: 5) { app.buttons["dismissHealthExplainer"].tap() }
        navigate(4, in: app)
        XCTAssertTrue(app.staticTexts["coachTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["coachUnavailable"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["coachSendOrStop"].isEnabled)
        XCTAssertFalse(app.staticTexts["FITOUT COACH"].exists)
    }
    @MainActor func testOnboardingCompletionAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-profile", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["getStartedButton"].waitForExistence(timeout: 10))
        let startSlider = app.buttons["getStartedButton"]
        startSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: startSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))
        app.textFields["nameField"].tap()
        app.textFields["nameField"].typeText("Test User\n")
        app.buttons["nextButton"].tap()
        XCTAssertTrue(app.otherElements["agePicker"].waitForExistence(timeout: 3))
        app.buttons["nextButton"].tap()
        XCTAssertTrue(app.otherElements["heightPicker"].waitForExistence(timeout: 3))
        app.buttons["nextButton"].tap()
        XCTAssertTrue(app.otherElements["weightRuler"].waitForExistence(timeout: 3))
        app.buttons["nextButton"].tap()
        app.buttons["Build muscle"].tap()
        let slider = app.buttons["createJourneySlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        XCTAssertTrue(app.buttons["navigationMenuButton"].waitForExistence(timeout: 5))
        if app.buttons["dismissHealthExplainer"].waitForExistence(timeout: 3) { app.buttons["dismissHealthExplainer"].tap() }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["navigationMenuButton"].waitForExistence(timeout: 10))
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
        navigate(1, in: app)
        XCTAssertTrue(app.buttons["gymSetupRoutine"].waitForExistence(timeout: 3))
        reveal(app.buttons["gymMyRoutines"], in: app)
        app.buttons["gymMyRoutines"].tap()
        app.buttons["newRoutine"].tap()
        reveal(app.buttons["Full Body"], in: app)
        app.buttons["Full Body"].tap()
        app.buttons["createRoutineContinue"].tap()
        XCTAssertTrue(app.navigationBars["Create routine"].waitForExistence(timeout: 3))
        app.buttons["routineStage-review"].tap()
        app.buttons["saveRoutine"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Full Body")).firstMatch.waitForExistence(timeout: 3))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Full Body")).firstMatch.tap()
        app.buttons["routineStage-schedule"].tap()
        XCTAssertTrue(app.textFields["routineName"].waitForExistence(timeout: 3))
        app.buttons["closeRoutine"].tap()
        app.navigationBars["My routines"].buttons.firstMatch.tap()
        reveal(app.buttons["gymExercises"], in: app)
        app.buttons["gymExercises"].tap()
        XCTAssertTrue(app.navigationBars["Exercise library"].waitForExistence(timeout: 3))
        app.buttons["Filter by muscle"].tap()
        XCTAssertTrue(app.navigationBars["Muscle map"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["muscle-chest"].waitForExistence(timeout: 5))
        app.buttons["muscle-chest"].tap()
        XCTAssertTrue(app.staticTexts["selectedMuscles"].label.contains("Chest"))
        app.buttons["Back"].tap()
        app.buttons["Done"].tap()
    }

    @MainActor func testCustomRoutineSetupThroughCompletedWorkout() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["navigationMenuButton"].waitForExistence(timeout: 10))
        navigate(1, in: app)
        reveal(app.buttons["gymSetupRoutine"], in: app)
        app.buttons["gymSetupRoutine"].tap()
        app.buttons["Build from scratch"].tap()
        app.buttons["createRoutineContinue"].tap()
        let day = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        XCTAssertTrue(app.textFields["routineName"].waitForExistence(timeout: 3))
        app.buttons["routineTrainingDay-\(day)"].tap()
        app.buttons["routineContinue"].tap()
        app.buttons["routineAddExercises"].tap()
        XCTAssertTrue(app.buttons["pickExercise-bench"].waitForExistence(timeout: 3))
        app.buttons["pickExercise-bench"].tap()
        app.buttons["confirmRoutineExercises"].tap()
        XCTAssertTrue(app.buttons["routineExercise-bench"].waitForExistence(timeout: 3))
        app.buttons["routineExercise-bench"].tap()
        XCTAssertTrue(app.buttons["routineAddSet"].waitForExistence(timeout: 3))
        app.buttons["closeRoutine"].tap()
        app.terminate()
        app.launch()
        navigate(1, in: app)
        reveal(app.buttons["gymSetupRoutine"], in: app)
        app.buttons["gymSetupRoutine"].tap()
        XCTAssertTrue(app.staticTexts["Unsaved draft restored"].waitForExistence(timeout: 3))
        app.buttons["routineStage-review"].tap()
        app.buttons["saveRoutine"].tap()
        XCTAssertTrue(app.buttons["gymStartWorkout"].waitForExistence(timeout: 5))
        reveal(app.buttons["gymStartWorkout"], in: app)
        app.buttons["gymStartWorkout"].tap()
        reveal(app.buttons["completeSet"].firstMatch, in: app)
        app.buttons["completeSet"].firstMatch.tap()
        reveal(app.buttons["finishWorkout"], in: app)
        app.buttons["finishWorkout"].tap()
        app.buttons["Complete workout"].tap()
        XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["gymWorkoutSummary"].waitForExistence(timeout: 5))
    }

    @MainActor func testWorkoutSetSurvivesTerminationAndFinishes() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-session", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["navigationMenuButton"].waitForExistence(timeout: 10))
        navigate(1, in: app)
        reveal(app.buttons["startQuickWorkout"], in: app)
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
        navigate(1, in: app)
        XCTAssertTrue(app.buttons["resumeWorkout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5) || app.buttons["resumeWorkout"].exists)
        if !app.navigationBars["Workout"].exists { reveal(app.buttons["resumeWorkout"], in: app); app.buttons["resumeWorkout"].tap() }
        XCTAssertTrue(app.buttons["completeSet"].firstMatch.label.contains("completed"))
        app.swipeUp()
        app.buttons["finishWorkout"].tap()
        app.buttons["Complete workout"].tap()
        XCTAssertTrue(app.navigationBars["Workout summary"].waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        reveal(app.buttons["Analytics and calendar"], in: app)
        app.buttons["Analytics and calendar"].tap()
        XCTAssertTrue(app.navigationBars["Analytics"].waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if app.buttons["Prepare CSV export"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["Prepare CSV export"].tap()
        XCTAssertTrue(app.buttons["Share export"].waitForExistence(timeout: 3))
    }

}
