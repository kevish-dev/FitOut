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

    func testWeeklyPlanAlwaysOpensScheduleIncludingEveryRestAndOpenDay() {
        var routine = RoutineTemplate.fullBody.make()
        for day in 19...25 {
            let weekday = RoutineSchedule.weekday(for: date(day), calendar: calendar)
            for kind in [RoutineDayKind.rest, .flexible] {
                routine.days[weekday].kind = kind
                let saved = RoutineDraft(routine: routine, stage: .review, weekday: weekday)
                guard case let .routine(value, selectedDay, stage) = GymNavigation.plan(active: routine, draft: saved, weekly: true) else {
                    return XCTFail("Weekly plan must open the existing editor")
                }
                XCTAssertEqual(value, routine); XCTAssertNil(selectedDay); XCTAssertEqual(stage, .schedule)
                let entry = RoutineEditorEntry.resolve(isSaved: true, draft: saved, initialWeekday: selectedDay, initialStage: stage, now: date(day), calendar: calendar)
                XCTAssertEqual(entry.stage, .schedule)
                XCTAssertEqual(routine.days[weekday].kind, kind)
            }
        }
    }

    func testExplicitRestDayTapOpensThatDayWhileDraftResumeKeepsItsStage() {
        let routine = RoutineTemplate.fullBody.make()
        let draft = RoutineDraft(routine: routine, stage: .review, weekday: 4)
        guard case let .routine(_, weekday, stage) = GymNavigation.plan(active: routine, draft: draft, weekday: 1) else { return XCTFail("Missing day editor") }
        let entry = RoutineEditorEntry.resolve(isSaved: true, draft: draft, initialWeekday: weekday, initialStage: stage, now: date(20), calendar: calendar)
        XCTAssertEqual(entry.weekday, 1); XCTAssertEqual(entry.stage, .workouts)
        XCTAssertEqual(routine.days[1].kind, .rest)
        let resumed = RoutineEditorEntry.resolve(isSaved: true, draft: draft, initialWeekday: nil, initialStage: nil, now: date(20), calendar: calendar)
        XCTAssertEqual(resumed.stage, .review); XCTAssertEqual(resumed.weekday, 4)
    }

    func testPlanWithoutRoutineUsesCreationAndUnsavedDraftCanResume() {
        guard case .create(let weekday, let active) = GymNavigation.plan(active: nil, draft: nil, weekday: 6, weekly: true) else { return XCTFail("Expected creation") }
        XCTAssertEqual(weekday, 6); XCTAssertTrue(active)
        let draft = RoutineDraft(routine: RoutineTemplate.custom.make(), stage: .schedule, weekday: 0)
        guard case .routine(let routine, _, _) = GymNavigation.plan(active: nil, draft: draft) else { return XCTFail("Expected draft") }
        XCTAssertEqual(routine.id, draft.routine.id)
    }

    func testRapidPlanAndQuickWorkoutTapsCannotPresentCompetingSheets() {
        let routine = RoutineTemplate.fullBody.make()
        let plan = GymNavigation.plan(active: routine, draft: nil, weekly: true)
        var navigation = GymNavigation()
        for _ in 0..<50 {
            XCTAssertTrue(navigation.present(plan))
            let id = navigation.destination?.id
            XCTAssertFalse(navigation.present(.workout))
            XCTAssertFalse(navigation.present(plan))
            XCTAssertEqual(navigation.destination?.id, id)
            navigation.dismiss()
            XCTAssertTrue(navigation.present(.workout))
            XCTAssertFalse(navigation.present(plan))
            navigation.dismiss()
            XCTAssertNil(navigation.destination)
        }
    }

    func testEditorEntryRejectsInvalidSavedWeekdayWithoutIndexingOutsideWeek() {
        let draft = RoutineDraft(routine: RoutineTemplate.fullBody.make(), stage: .workouts, weekday: 99)
        let entry = RoutineEditorEntry.resolve(isSaved: true, draft: draft, initialWeekday: -1, initialStage: nil, now: date(20), calendar: calendar)
        XCTAssertEqual(entry.weekday, 1); XCTAssertEqual(entry.stage, .workouts)
    }

    @MainActor func testQuickWorkoutOnRestDayStartsAndFinishesWithoutRewritingWeeklyPlan() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let gym = try GymStore(container: database), workouts = try WorkoutStore(container: database)
        var routine = RoutineTemplate.fullBody.make(); routine.isActive = true
        XCTAssertTrue(gym.save(routine))
        let saved = try XCTUnwrap(gym.activeRoutine), now = date(20)
        XCTAssertEqual(GymLandingState.today(routine: saved, sessions: [], now: now, calendar: calendar), .rest)
        var setup = QuickWorkoutDraft()
        setup.add([ExerciseCatalogue.all[0]], current: nil, history: [])
        setup.entries[0].sets = [WorkoutSet(reps: 8, loadKG: 20)]
        XCTAssertNil(workouts.active) // Opening/configuring still does not start a session.
        XCTAssertTrue(workouts.startQuickWorkout(setup, unit: .kg, now: now))
        let running = try XCTUnwrap(workouts.active)
        XCTAssertNil(running.routineID)
        XCTAssertEqual(GymLandingState.today(routine: saved, sessions: workouts.sessions, now: now, calendar: calendar), .active(running))
        XCTAssertTrue(workouts.pause(now: now.addingTimeInterval(5)))
        let paused = try XCTUnwrap(workouts.active)
        XCTAssertEqual(GymLandingState.today(routine: saved, sessions: workouts.sessions, now: now.addingTimeInterval(5), calendar: calendar), .active(paused))
        XCTAssertTrue(workouts.resume(now: now.addingTimeInterval(10)))
        XCTAssertTrue(workouts.performFocused(.completeSet, sessionID: running.id, now: now.addingTimeInterval(30)))
        XCTAssertNil(workouts.active)
        XCTAssertEqual(workouts.history.first?.status, .completed)
        try gym.reload()
        XCTAssertEqual(gym.activeRoutine, saved)
        XCTAssertEqual(gym.activeRoutine?.days[1].kind, .rest)
        guard case .routine(_, _, .schedule) = GymNavigation.plan(active: gym.activeRoutine, draft: nil, weekly: true) else { return XCTFail("Plan must still open after the quick workout") }
    }

    @MainActor func testRestAndOpenDaysNeverStartAnEmptyPlannedSession() throws {
        let workouts = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        for kind in [RoutineDayKind.rest, .flexible] {
            let day = RoutineDay(weekday: 1, kind: kind)
            XCTAssertFalse(workouts.start(day: day, catalogue: ExerciseCatalogue.all, now: date(20)))
            XCTAssertNil(workouts.active); XCTAssertTrue(workouts.sessions.isEmpty)
        }
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
