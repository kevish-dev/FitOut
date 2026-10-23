import XCTest
@testable import FitOut

final class GymLandingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 1 // Gym weeks must still start on Monday.
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func session(on day: Int, routine: Routine? = nil, status: SessionStatus = .completed) -> WorkoutSession {
        WorkoutSession(routineID: routine?.id, title: "Logged workout", startedAt: date(day, hour: 9),
                       endedAt: status == .inProgress || status == .paused ? nil : date(day, hour: 10), status: status)
    }

    func testSetupAndIncompleteDaysNeverOfferAnEmptyPlannedWorkout() {
        XCTAssertEqual(GymLandingState.today(routine: nil, sessions: [], now: date(19), calendar: calendar), .setup)
        XCTAssertEqual(GymLandingState.today(routine: RoutineTemplate.custom.make(), sessions: [], now: date(19), calendar: calendar), .setup)
        var routine = RoutineTemplate.fullBody.make()
        routine.days[0].exercises = []
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [], now: date(19), calendar: calendar), .needsExercises(routine.days[0]))
    }

    func testTodayDistinguishesTrainingRestAndUnassignedDays() {
        var routine = RoutineTemplate.fullBody.make()
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [], now: date(19), calendar: calendar), .scheduled(routine.days[0]))
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [], now: date(20), calendar: calendar), .rest)
        routine.days[1].kind = .flexible
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [], now: date(20), calendar: calendar), .unassigned)
    }

    func testResumeTakesPriorityEvenWithoutRoutineAndAcrossMidnight() {
        let active = session(on: 18, status: .paused)
        XCTAssertEqual(GymLandingState.today(routine: nil, sessions: [active], now: date(19), calendar: calendar), .active(active))
    }

    func testQuickWorkoutDoesNotHideScheduledWorkoutAndPlanEditsKeepCompletion() {
        var routine = RoutineTemplate.fullBody.make()
        let quick = session(on: 19)
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [quick], now: date(19), calendar: calendar), .scheduled(routine.days[0]))
        let logged = session(on: 19, routine: routine)
        routine.days[0].title = "Renamed after training"
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [logged, quick], now: date(19), calendar: calendar), .completed(logged))
        let anotherRoutine = RoutineTemplate.ppl.make()
        XCTAssertEqual(GymLandingState.today(routine: anotherRoutine, sessions: [logged], now: date(19), calendar: calendar), .scheduled(anotherRoutine.days[0]))
    }

    func testOvernightCompletionDoesNotCompleteTheNextScheduledDay() {
        let routine = RoutineTemplate.ppl.make()
        var overnight = session(on: 19, routine: routine)
        overnight.endedAt = date(20, hour: 1)
        XCTAssertEqual(GymLandingState.today(routine: routine, sessions: [overnight], now: date(20), calendar: calendar), .scheduled(routine.days[1]))
    }

    func testWeekIsMondayToSundayAndNeverInventsPastAttendance() {
        let routine = RoutineTemplate.ppl.make()
        let completed = session(on: 19, routine: routine)
        let days = GymLandingState.week(routine: routine, sessions: [completed], now: date(22), calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first?.date, calendar.startOfDay(for: date(19)))
        XCTAssertEqual(days.last?.date, calendar.startOfDay(for: date(25)))
        XCTAssertEqual(days.map(\.weekday), Array(0..<7))
        XCTAssertEqual(days.filter(\.isToday).map(\.weekday), [3])
        XCTAssertEqual(days[0].status, .completed)
        XCTAssertEqual(days[0].title, completed.title)
        XCTAssertEqual(days[1].status, .noLog)
        XCTAssertEqual(days[1].title, "No workout logged")
        XCTAssertEqual(days[3].status, .rest)
        XCTAssertEqual(days[4].status, .planned)
        XCTAssertEqual(days[4].plan?.exercises.count, routine.days[4].exercises.count)
    }

    func testFutureWeeksHaveNoCompletedStatusAndUnassignedIsValid() {
        let nextWeek = GymLandingState.week(routine: nil, sessions: [], offset: 1, now: date(22), calendar: calendar)
        XCTAssertEqual(nextWeek.first?.date, calendar.startOfDay(for: date(26)))
        XCTAssertTrue(nextWeek.allSatisfy { $0.status == .unassigned && !$0.isToday })
    }

    func testProgressUsesOnlyFinishedNonfutureSessionsInMondayWeek() {
        let priorSunday = session(on: 18)
        let monday = session(on: 19)
        let today = session(on: 24)
        var futureEnd = session(on: 24)
        futureEnd.endedAt = date(25)
        let input = [priorSunday, monday, today, futureEnd, session(on: 25),
                     session(on: 24, status: .skipped), session(on: 24, status: .abandoned), session(on: 24, status: .inProgress)]
        let result = GymLandingState.completedThisWeek(input, now: date(24), calendar: calendar)
        XCTAssertEqual(result.map(\.id), [today.id, monday.id])
        XCTAssertTrue(GymLandingState.completedThisWeek([], now: date(24), calendar: calendar).isEmpty)
    }

    func testCalendarDaysRemainSevenAcrossDaylightSavingChange() {
        var localCalendar = calendar
        localCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = localCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let days = GymLandingState.week(routine: nil, sessions: [], now: now, calendar: localCalendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(Set(days.map(\.date)).count, 7)
        XCTAssertEqual(localCalendar.component(.weekday, from: days[0].date), 2)
        XCTAssertEqual(localCalendar.component(.weekday, from: days[6].date), 1)
    }
}
