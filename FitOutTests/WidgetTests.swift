import XCTest
@testable import FitOut

final class WidgetTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }
    func testWaterCombinesOnlyTodaysHealthAndLocalReadingsAcrossMidnight() {
        var state = FitOutWidgetState()
        state.snapshot.health = WidgetHealthReading(measuredAt: date(7), waterML: 600, steps: 100)
        state.water = [WidgetWaterLog(date: date(7), milliliters: 150), WidgetWaterLog(date: date(8, hour: 8), milliliters: 500)]
        XCTAssertEqual(state.totalWater(at: date(7), calendar: calendar), 750)
        XCTAssertEqual(state.totalWater(at: date(8), calendar: calendar), 500)
        XCTAssertFalse(state.snapshot.health.isCurrent(at: date(8), calendar: calendar))
        XCTAssertEqual(state.totalWater(at: date(9), calendar: calendar), 0)
    }
    func testStreakCountsDistinctDatesAndSurvivesDSTAndEndsAfterMissedDay() {
        var state = FitOutWidgetState()
        state.snapshot.completedDays = [date(6), date(7), date(8), date(8, hour: 18)]
        XCTAssertEqual(state.streak(at: date(8, hour: 20), calendar: calendar), 3)
        XCTAssertEqual(state.streak(at: date(9), calendar: calendar), 3)
        XCTAssertEqual(state.streak(at: date(10), calendar: calendar), 0)
        XCTAssertEqual(state.weekDays(at: date(8), calendar: calendar).count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: state.weekDays(at: date(8), calendar: calendar)[0]), 1)
    }
    func testFileTransactionsPreserveGoalsAndWaterWhenSnapshotChangesAndUndoUsesExactID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = WidgetSharedStore(directory: directory)
        let widget = WidgetSharedStore(directory: directory)
        XCTAssertNil(try app.read().snapshot.updatedAt)
        let first = try widget.logWater(150, at: date(8, hour: 8)).water[0]
        let second = try app.logWater(500, at: date(8, hour: 9)).water[1]
        let goals = WidgetGoals(waterML: 2_000, steps: 8_000)
        try app.saveGoals(goals)
        try app.update { $0.snapshot.onboarded = true; $0.snapshot.updatedAt = self.date(8) }
        XCTAssertEqual(try widget.read().water.map(\.id), [first.id, second.id])
        XCTAssertEqual(try widget.read().goals, goals)
        try widget.removeWater(id: first.id)
        try widget.removeWater(id: first.id)
        XCTAssertEqual(try app.read().water.map(\.id), [second.id])
        XCTAssertEqual(try app.read().totalWater(at: date(8), calendar: calendar), 500)
        XCTAssertThrowsError(try widget.logWater(0))
        XCTAssertThrowsError(try widget.logWater(5_001))
        XCTAssertThrowsError(try app.saveGoals(WidgetGoals(waterML: .nan)))
        XCTAssertEqual(try app.read().goals, goals)
    }
    func testRestProtectedWidgetStreakMatchesAppAndOldCachesStillDecode() throws {
        var state = FitOutWidgetState()
        state.snapshot.completedDays = [date(7), date(9)]
        state.snapshot.restSchedules = [StreakRestSchedule(effectiveFrom: date(1), validFrom: nil, weekdays: [6])]
        let sessions = state.snapshot.completedDays.map { WorkoutSession(title: "Training", startedAt: $0, status: .completed) }
        let app = WorkoutAnalytics.dailyStreak(sessions, restSchedules: state.snapshot.restSchedules!, now: date(9), calendar: calendar)
        XCTAssertEqual(state.streak(at: date(9), calendar: calendar), 2)
        XCTAssertEqual(state.streak(at: date(9), calendar: calendar), app.consecutiveDays)
        XCTAssertTrue(state.isRestDay(date(8), calendar: calendar))
        XCTAssertFalse(state.completed(on: date(8), through: date(9), calendar: calendar))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(FitOutWidgetState.self, from: data).streak(at: date(9), calendar: calendar), 2)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var snapshot = try XCTUnwrap(old["snapshot"] as? [String: Any]); snapshot.removeValue(forKey: "restSchedules"); old["snapshot"] = snapshot
        let legacy = try JSONDecoder().decode(FitOutWidgetState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.snapshot.restSchedules)
        XCTAssertEqual(legacy.streak(at: date(9), calendar: calendar), 1)
    }
    func testCorruptOrNewerDataIsNotSilentlyReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSharedStore(directory: directory)
        try store.update { $0.version = 2 }
        XCTAssertThrowsError(try store.logWater(150))
        let file = directory.appendingPathComponent("state.json")
        let invalid = Data("preserve this unreadable data".utf8)
        try invalid.write(to: file)
        XCTAssertThrowsError(try store.logWater(150))
        XCTAssertEqual(try Data(contentsOf: file), invalid)
    }
    func testGoalsAreOptionalAndRoutesAreStrictlyValidated() {
        XCTAssertTrue(WidgetGoals().isValid)
        XCTAssertFalse(WidgetGoals(steps: -1).isValid)
        XCTAssertFalse(WidgetGoals(sleepHours: 25).isValid)
        for destination in WidgetDestination.allCases { XCTAssertEqual(WidgetDestination(url: destination.url), destination) }
        for url in ["https://widget/water", "fitout://other/water", "fitout://widget/delete", "fitout://widget/water?amount=500", "fitout://widget/startWorkout/extra"] {
            XCTAssertNil(WidgetDestination(url: URL(string: url)!))
        }
    }
    func testWeeklyVolumeAndScheduleDoNotLeakIntoNextWeekOrDay() {
        var state = FitOutWidgetState()
        let start = calendar.dateInterval(of: .weekOfYear, for: date(8))!.start
        state.snapshot.volumeWeeks = [WidgetVolumeWeek(date: start, kilograms: 1_500)]
        state.snapshot.plans = [WidgetWorkoutPlan(date: date(8), title: "Legs", kind: "Workout", exercises: ["Squat"], exerciseCount: 1, minutes: 30)]
        XCTAssertEqual(state.volume(at: date(8), calendar: calendar), 1_500)
        XCTAssertNil(state.volume(at: date(16), calendar: calendar))
        XCTAssertEqual(state.plan(at: date(8), calendar: calendar)?.title, "Legs")
        XCTAssertNil(state.plan(at: date(9), calendar: calendar))
    }
}
