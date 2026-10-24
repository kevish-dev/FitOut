import XCTest
@testable import FitOut
final class HomeStateTests: XCTestCase {
    func testWeeklyWorkoutTimeIncludesActiveAndCompletedTimeWithoutPauses() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!; calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let monday = week.start.addingTimeInterval(12 * 3600)
        let completed = WorkoutSession(title: "Monday", startedAt: monday, endedAt: monday.addingTimeInterval(3600), status: .completed, pausedSeconds: 600)
        let active = WorkoutSession(title: "Now", startedAt: now.addingTimeInterval(-1800), pausedSeconds: 300)
        let result = HomeStateResolver.weeklyWorkoutTime([completed, active], now: now, calendar: calendar)
        XCTAssertEqual(result.total, 1.25)
        XCTAssertEqual(result.buckets.count, 7)
        XCTAssertEqual(result.buckets[0], 3000)
        XCTAssertEqual(result.buckets[5], 1500)
        XCTAssertEqual(result.buckets.reduce(0, +), 4500)
    }

    func testWeeklyWorkoutTimeFreezesPausedSessionAndExcludesOtherWeeksAndUnfinishedHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        let paused = WorkoutSession(title: "Paused", startedAt: now.addingTimeInterval(-1800), status: .paused,
            pausedAt: now.addingTimeInterval(-600), pausedSeconds: 300)
        let previous = WorkoutSession(title: "Previous", startedAt: week.start.addingTimeInterval(-7200), endedAt: week.start.addingTimeInterval(-3600), status: .completed)
        let skipped = WorkoutSession(title: "Skipped", startedAt: now.addingTimeInterval(-3600), endedAt: now, status: .skipped)
        var abandoned = skipped; abandoned.status = .abandoned
        let future = WorkoutSession(title: "Future", startedAt: now.addingTimeInterval(1))
        let badEnd = WorkoutSession(title: "Missing end", startedAt: now.addingTimeInterval(-3600), status: .completed)
        let result = HomeStateResolver.weeklyWorkoutTime([paused, previous, skipped, abandoned, future, badEnd], now: now, calendar: calendar)
        XCTAssertEqual(result.total, 0.25)
        XCTAssertEqual(HomeStateResolver.weeklyWorkoutTime([paused], now: now.addingTimeInterval(120), calendar: calendar).total, 0.25)
        XCTAssertEqual(HomeStateResolver.weeklyWorkoutTime([], now: now, calendar: calendar).total, 0)
    }

    func testWorkoutTimeUsesCalendarWeekInsteadOfRollingSevenDaysAndResetsAtBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!; calendar.firstWeekday = 2
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let sunday = monday.addingTimeInterval(-7200)
        let excluded = WorkoutSession(title: "Sunday", startedAt: sunday, endedAt: sunday.addingTimeInterval(3600), status: .completed)
        let included = WorkoutSession(title: "Monday", startedAt: monday, endedAt: monday.addingTimeInterval(3600), status: .completed)
        let now = monday.addingTimeInterval(7200)
        XCTAssertEqual(HomeStateResolver.weeklyWorkoutTime([excluded, included], now: now, calendar: calendar).total, 1)
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: monday)!
        XCTAssertEqual(HomeStateResolver.weeklyWorkoutTime([included], now: nextWeek, calendar: calendar).total, 0)
    }

    func testWorkoutTimeDailyBucketsRespectDaylightSavingCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!; calendar.firstWeekday = 1
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 30))!
        let completed = WorkoutSession(title: "After DST", startedAt: start, endedAt: start.addingTimeInterval(1800), status: .completed)
        let result = HomeStateResolver.weeklyWorkoutTime([completed], now: start.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(result.total, 0.5)
        XCTAssertEqual(result.buckets[1], 1800)
        XCTAssertEqual(result.buckets[0], 0)
    }

    func testNoRoutineAndFlexibleDayAreDistinct() {
        XCTAssertEqual(HomeStateResolver.workout(HomeWorkoutInput()), .noRoutine)
        XCTAssertEqual(HomeStateResolver.workout(HomeWorkoutInput(hasRoutine: true)), .flexible)
        var noRoutine = HomeWorkoutInput()
        noRoutine.completion = ("Quick workout", 3, 900, 120)
        XCTAssertEqual(HomeStateResolver.workout(noRoutine), .noRoutine)
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

final class HomeInsightTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }
    private func fixture(reps: Int = 12, effort: Double? = 7.5) -> (Routine, [WorkoutSession]) {
        var routine = Routine(name: "Strength", isActive: true)
        routine.updatedAt = date(1)
        routine.days[0].kind = .workout
        routine.days[0].title = "Push"
        routine.days[0].exercises = [PlannedExercise(exerciseID: "bench", loadKG: 60)]
        let sessions = [9, 16, 23].map { day in
            WorkoutSession(routineID: routine.id, title: "Push", startedAt: date(day),
                           endedAt: date(day).addingTimeInterval(3600), status: .completed,
                           entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: (0..<3).map { _ in
                WorkoutSet(reps: reps, loadKG: 60, rpe: effort, completedAt: date(day).addingTimeInterval(1800))
            })])
        }
        return (routine, sessions)
    }
    private func candidates(_ routine: Routine, _ sessions: [WorkoutSession]) -> [HomeWorkoutInsight] {
        HomeInsightPolicy.candidates(sessions: sessions, routine: routine, unit: .kg,
                                     now: date(23).addingTimeInterval(6 * 3600), calendar: calendar)
    }

    func testInsightRequiresRepeatedRecentEvidenceAndCurrentPlan() {
        let (routine, sessions) = fixture()
        let insights = candidates(routine, sessions)
        XCTAssertEqual(insights.count, 1)
        guard let insight = insights.first else { return XCTFail("Expected supported rep-ceiling evidence") }
        XCTAssertEqual(insights.first?.exerciseID, "bench")
        XCTAssertTrue(insight.text.contains("60 kg"))
        XCTAssertEqual(insight.sourceSessions.count, 3)
        XCTAssertTrue(candidates(routine, Array(sessions.prefix(2))).isEmpty)
        var edited = routine
        edited.updatedAt = date(23).addingTimeInterval(7200)
        XCTAssertTrue(candidates(edited, sessions).isEmpty)
        XCTAssertTrue(HomeInsightPolicy.candidates(sessions: sessions, routine: routine, unit: .kg,
                                                   now: date(31), calendar: calendar).isEmpty)
    }

    func testMissingEffortIncompleteSetsAndConflictingTargetsHideInsight() {
        let (routine, missingEffort) = fixture(effort: nil)
        XCTAssertTrue(candidates(routine, missingEffort).isEmpty)
        let (_, highEffort) = fixture(effort: 9.5)
        // Keep the matching routine ID while testing high-effort ceiling sets.
        var matching = highEffort
        for index in matching.indices { matching[index].routineID = routine.id }
        XCTAssertTrue(candidates(routine, matching).isEmpty)
        var (_, incomplete) = fixture()
        for index in incomplete.indices { incomplete[index].routineID = routine.id }
        incomplete[2].entries[0].sets[0].completedAt = nil
        XCTAssertTrue(candidates(routine, incomplete).isEmpty)
        var conflicting = routine
        conflicting.days[1].kind = .workout
        conflicting.days[1].title = "Other push"
        conflicting.days[1].exercises = [PlannedExercise(exerciseID: "bench", repMax: 15, loadKG: 60)]
        var valid = fixture().1
        for index in valid.indices { valid[index].routineID = routine.id }
        XCTAssertTrue(candidates(conflicting, valid).isEmpty)
    }

    func testRepeatedShortfallCanProduceOneSpecificInsight() {
        let (routine, sessions) = fixture(reps: 7, effort: 9.5)
        let insights = candidates(routine, sessions)
        XCTAssertEqual(insights.count, 1)
        guard let insight = insights.first else { return XCTFail("Expected supported rep-shortfall evidence") }
        XCTAssertTrue(insight.text.contains("8-rep target"))
        XCTAssertTrue(insight.text.contains("Review the planned load"))
    }

    func testSameDayAndUnfinishedSessionsDoNotCreateEnoughEvidence() {
        let (routine, sessions) = fixture()
        var sameDay = sessions
        for index in sameDay.indices { sameDay[index].startedAt = date(23) }
        XCTAssertTrue(candidates(routine, sameDay).isEmpty)
        var unfinished = sessions
        unfinished[2].status = .inProgress
        XCTAssertTrue(candidates(routine, unfinished).isEmpty)
    }

    func testGenericProseAndUnknownModelChoicesAreRejected() {
        XCTAssertEqual(HomeInsightPolicy.selectedIndex("C0\n", count: 1), 0)
        XCTAssertNil(HomeInsightPolicy.selectedIndex("NONE", count: 1))
        XCTAssertNil(HomeInsightPolicy.selectedIndex("C9", count: 1))
        XCTAssertNil(HomeInsightPolicy.selectedIndex("C0: stay consistent!", count: 1))
    }

    @MainActor func testUnavailableOrInsufficientDataNeverCallsModel() async {
        let selector = InsightSelectorStub(index: 0)
        let (routine, sessions) = fixture()
        let evidence = candidates(routine, sessions)
        let unavailable = await HomeInsightEngine.insight(for: .init(isAvailable: false, candidates: evidence), selector: selector)
        let insufficient = await HomeInsightEngine.insight(for: .init(isAvailable: true, candidates: []), selector: selector)
        XCTAssertNil(unavailable)
        XCTAssertNil(insufficient)
        XCTAssertEqual(selector.calls, 0)
    }

    @MainActor func testOnlyValidSelectionIsDisplayedAndErrorsHideSection() async {
        let (routine, sessions) = fixture()
        let request = HomeInsightRequest(isAvailable: true, candidates: candidates(routine, sessions))
        let selector = InsightSelectorStub(index: 0)
        let selected = await HomeInsightEngine.insight(for: request, selector: selector)
        XCTAssertEqual(selected, request.candidates.first)
        selector.index = 99
        let invalid = await HomeInsightEngine.insight(for: request, selector: selector)
        XCTAssertNil(invalid)
        selector.index = nil
        let noUsefulInsight = await HomeInsightEngine.insight(for: request, selector: selector)
        XCTAssertNil(noUsefulInsight)
        selector.shouldFail = true
        let failed = await HomeInsightEngine.insight(for: request, selector: selector)
        XCTAssertNil(failed)
    }
}

@MainActor private final class InsightSelectorStub: HomeInsightSelecting {
    var index: Int?
    var calls = 0
    var shouldFail = false
    init(index: Int?) { self.index = index }
    func select(from candidates: [HomeWorkoutInsight]) async throws -> Int? {
        calls += 1
        if shouldFail { throw CancellationError() }
        return index
    }
}
