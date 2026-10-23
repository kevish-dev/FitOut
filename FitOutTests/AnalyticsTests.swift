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
    func testRecentWeeklyVolumeUsesCompletedWeightedSetsAndKeepsEmptyWeeks() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
        }
        func session(_ day: Int, load: Double, type: SetType = .working, status: SessionStatus = .completed) -> WorkoutSession {
            var result = WorkoutSession(title: "Strength", startedAt: date(day), status: status)
            result.entries = [WorkoutEntry(exercise: ExerciseCatalogue.all[0],
                                           sets: [WorkoutSet(type: type, reps: 10, loadKG: load, completedAt: date(day))])]
            return result
        }
        let now = date(23).addingTimeInterval(6 * 3600)
        let sessions = [session(23, load: 50), session(16, load: 40),
                        session(22, load: 100, type: .warmup),
                        session(22, load: 100, status: .inProgress),
                        session(24, load: 100)]
        let trend = WorkoutAnalytics.recentWeeklyVolume(sessions, now: now, calendar: calendar)
        XCTAssertEqual(trend.weeks.count, 6)
        XCTAssertEqual(trend.weeks.filter { $0.volumeKG == 0 }.count, 4)
        XCTAssertEqual(trend.currentWeekKG, 500)
        XCTAssertEqual(trend.previousWeekKG, 400)
        XCTAssertEqual(trend.peakKG, 500)
        XCTAssertTrue(trend.weeks.last!.isCurrent)
        XCTAssertFalse(WorkoutAnalytics.recentWeeklyVolume([], now: now, calendar: calendar).hasVolume)
    }
    func testDailyStreakCountsUniqueCompletedDaysAndMatchesWeeklyChecks() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let now = date(23, 18)
        let completed = [20, 21, 22, 23, 23].map { WorkoutSession(title: "Training", startedAt: date($0), status: .completed) }
        let skipped = WorkoutSession(title: "Skipped", startedAt: date(19), status: .skipped)
        let unfinished = WorkoutSession(title: "Active", startedAt: date(19), status: .inProgress)
        let future = WorkoutSession(title: "Future", startedAt: date(24), status: .completed)
        let result = WorkoutAnalytics.dailyStreak(completed + [skipped, unfinished, future], now: now, calendar: calendar)
        XCTAssertEqual(result.consecutiveDays, 4)
        XCTAssertEqual(result.completedDaysThisWeek, 4)
        XCTAssertEqual(result.weekDays.count, 7)
        XCTAssertEqual(result.weekDays.map(\.isCompleted), [false, false, true, true, true, true, false])
    }
    func testDailyStreakAllowsYesterdayButBreaksAfterMissingTwoDays() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))! }
        let sessions = [21, 22].map { WorkoutSession(title: "Training", startedAt: date($0), status: .completed) }
        XCTAssertEqual(WorkoutAnalytics.dailyStreak(sessions, now: date(23), calendar: calendar).consecutiveDays, 2)
        XCTAssertEqual(WorkoutAnalytics.dailyStreak(sessions, now: date(24), calendar: calendar).consecutiveDays, 0)
    }
    func testDailyStreakUsesFinishDayAcrossMidnightAndWeekBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
        }
        let overnight = WorkoutSession(title: "Late workout", startedAt: date(7, 23, 50), endedAt: date(8, 0, 10), status: .completed)
        let result = WorkoutAnalytics.dailyStreak([overnight], now: date(8, 12), calendar: calendar)
        XCTAssertEqual(result.consecutiveDays, 1)
        XCTAssertEqual(result.completedDaysThisWeek, 1)
        XCTAssertTrue(calendar.isDate(result.weekDays[0].date, inSameDayAs: date(8, 12)))
        XCTAssertTrue(result.weekDays[0].isCompleted)
    }
    func testMuscleAllocationAndCSVQuoting() {
        var exercise = ExerciseCatalogue.all[0]; exercise.muscles = [.chest, .triceps]; exercise.name = "Press, \"test\""
        var session = WorkoutSession(title: "Training", status: .completed)
        session.entries = [WorkoutEntry(exercise: exercise, sets: [WorkoutSet(reps: 10, loadKG: 50, completedAt: .now)])]
        let totals = WorkoutAnalytics.muscleVolume([session]); XCTAssertEqual(totals[.chest], 250); XCTAssertEqual(totals[.triceps], 250)
        XCTAssertTrue(WorkoutAnalytics.csv([session]).contains("\"Press, \"\"test\"\"\""))
    }
}
