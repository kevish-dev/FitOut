import XCTest
@testable import FitOut
final class HomeStateTests: XCTestCase {
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
