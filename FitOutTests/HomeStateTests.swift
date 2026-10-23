import XCTest
@testable import FitOut
final class HomeStateTests: XCTestCase {
    func testNoRoutineAndFlexibleDayAreDistinct() {
        XCTAssertEqual(HomeStateResolver.workout(HomeWorkoutInput()), .noRoutine)
        XCTAssertEqual(HomeStateResolver.workout(HomeWorkoutInput(hasRoutine: true)), .flexible)
    }
    func testRestDayNeverBecomesMissedWorkout() {
        XCTAssertEqual(HomeStateResolver.workout(HomeWorkoutInput(hasRoutine: true, isRestDay: true, plannedTitle: "Old title")), .rest)
    }
    func testScheduledWorkoutAndCompletionPriority() {
        var input = HomeWorkoutInput(hasRoutine: true, plannedTitle: "Push", exerciseCount: 4, minutes: 45)
        XCTAssertEqual(HomeStateResolver.workout(input), .planned(title: "Push", exerciseCount: 4, minutes: 45))
        input.completion = ("Push", 12, 2400, 1800)
        XCTAssertEqual(HomeStateResolver.workout(input), .completed(title: "Push", sets: 12, seconds: 2400, volumeKG: 1800))
    }
}
