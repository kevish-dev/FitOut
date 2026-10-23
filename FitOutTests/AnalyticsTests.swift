import XCTest
@testable import FitOut
final class AnalyticsTests: XCTestCase {
    func testEpleyLimitsAndRepRecords() {
        XCTAssertEqual(WorkoutAnalytics.estimate1RM(load: 60, reps: 10)!, 80, accuracy: 0.0001)
        XCTAssertEqual(WorkoutAnalytics.estimate1RM(load: 60, reps: 1), 60)
        XCTAssertNil(WorkoutAnalytics.estimate1RM(load: .nan, reps: 3)); XCTAssertNil(WorkoutAnalytics.estimate1RM(load: 60, reps: 11))
        var session = WorkoutSession(title: "Strength", status: .completed)
        session.entries = [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(reps: 8, loadKG: 60, completedAt: .now), WorkoutSet(reps: 10, loadKG: 60, completedAt: .now)])]
        let records = WorkoutAnalytics.records(exerciseID: "bench", sessions: [session])
        XCTAssertEqual(records.repsAtLoad[60], 10); XCTAssertEqual(records.maxLoadKG, 60)
        session.status = .skipped; XCTAssertNil(WorkoutAnalytics.records(exerciseID: "bench", sessions: [session]).maxLoadKG)
    }
    func testWeeklyStreakDoesNotCountSkippedOrBreakForRestDays() {
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        let sessions = [0, -7, -14].map { WorkoutSession(title: "Training", startedAt: now.addingTimeInterval(Double($0 * 86400)), status: .completed) }
        XCTAssertEqual(WorkoutAnalytics.weeklyStreak(sessions, now: now, calendar: calendar), 3)
        XCTAssertEqual(WorkoutAnalytics.weeklyStreak([], now: now, calendar: calendar), 0)
        XCTAssertEqual(WorkoutAnalytics.weeklyStreak(sessions.map { var s = $0; s.status = .skipped; return s }, now: now, calendar: calendar), 0)
    }
    func testMuscleAllocationAndCSVQuoting() {
        var exercise = ExerciseCatalogue.all[0]; exercise.muscles = [.chest, .triceps]; exercise.name = "Press, \"test\""
        var session = WorkoutSession(title: "Training", status: .completed)
        session.entries = [WorkoutEntry(exercise: exercise, sets: [WorkoutSet(reps: 10, loadKG: 50, completedAt: .now)])]
        let totals = WorkoutAnalytics.muscleVolume([session]); XCTAssertEqual(totals[.chest], 250); XCTAssertEqual(totals[.triceps], 250)
        XCTAssertTrue(WorkoutAnalytics.csv([session]).contains("\"Press, \"\"test\"\"\""))
    }
}
