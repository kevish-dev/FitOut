import XCTest
@testable import FitOut

final class WorkoutStreakTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func completed(_ day: Int) -> WorkoutSession {
        WorkoutSession(title: "Training", startedAt: date(day).addingTimeInterval(-600), endedAt: date(day), status: .completed,
            entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(reps: 10, loadKG: 40, completedAt: date(day))])])
    }
    @MainActor private func defaults() -> UserDefaults { UserDefaults(suiteName: "streak-test-" + UUID().uuidString)! }

    @MainActor func testExistingHistoryEstablishesBaselineWithoutReplayingOldCelebrations() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let sessions = [completed(23), completed(24), completed(25)]
        let store = WorkoutStreakStore(defaults: prefs, sessions: sessions, now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
        store.update(sessions: sessions, now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
    }
    @MainActor func testFirstCompletionQueuesOneDayAndStartsDraftsDoNotQualify() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        let active = WorkoutSession(title: "Created", startedAt: date(25))
        store.update(sessions: [active], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
        var paused = active; paused.status = .paused
        store.update(sessions: [paused], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
        var done = completed(25); done.id = active.id
        store.update(sessions: [done], now: date(25, hour: 18), calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(store.pending).snapshot.consecutiveDays, 1)
        XCTAssertEqual(store.pending?.previousCount, 0)
        XCTAssertEqual(store.pending?.snapshot.completedDaysThisWeek, 1)
    }
    @MainActor func testSecondWorkoutSameDayDoesNotIncrementOrReplayAfterAcknowledgment() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        let one = completed(25), two = completed(25)
        store.update(sessions: [one], now: date(25, hour: 18), calendar: calendar)
        let id = try XCTUnwrap(store.pending?.id)
        store.update(sessions: [one, two], now: date(25, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.id, id); XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 1)
        store.acknowledge(id)
        store.update(sessions: [one, two], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
        XCTAssertNil(WorkoutStreakStore(defaults: prefs, sessions: [one, two], now: date(25, hour: 18), calendar: calendar).pending)
    }
    @MainActor func testConsecutiveCompletionMovesFromThreeToFourAndGapRestartsAtOne() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let previous = [completed(22), completed(23), completed(24)]
        let store = WorkoutStreakStore(defaults: prefs, sessions: previous, now: date(25), calendar: calendar)
        store.update(sessions: previous + [completed(25)], now: date(25, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.previousCount, 3); XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 4)
        store.acknowledge(try XCTUnwrap(store.pending?.id))
        let gap = previous + [completed(25), completed(28)]
        store.update(sessions: gap, now: date(28, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.previousCount, 0); XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 1)
    }
    @MainActor func testPendingAwardRestoresAfterRelaunchUntilContinued() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let sessions = [completed(25)]
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        store.update(sessions: sessions, now: date(25, hour: 18), calendar: calendar)
        let restored = WorkoutStreakStore(defaults: prefs, sessions: sessions, now: date(25, hour: 18), calendar: calendar)
        XCTAssertEqual(restored.pending?.id, store.pending?.id)
        restored.acknowledge(try XCTUnwrap(restored.pending?.id))
        XCTAssertNil(WorkoutStreakStore(defaults: prefs, sessions: sessions, now: date(25, hour: 18), calendar: calendar).pending)
    }
    @MainActor func testUndoOrDeletionCancelsPendingAndRecompletionDoesNotReplayAcknowledgedDay() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        let done = completed(25)
        store.update(sessions: [done], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNotNil(store.pending)
        var undone = done; undone.status = .inProgress; undone.endedAt = nil
        store.update(sessions: [undone], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
        store.update(sessions: [done], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNotNil(store.pending)
        store.acknowledge(try XCTUnwrap(store.pending?.id))
        store.update(sessions: [], now: date(25, hour: 18), calendar: calendar)
        store.update(sessions: [done], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
    }
    @MainActor func testDeletingOneOfTwoCompletionsKeepsThatDaysCredit() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        let first = completed(25), other = completed(25)
        store.update(sessions: [first, other], now: date(25, hour: 18), calendar: calendar)
        store.update(sessions: [other], now: date(25, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 1)
    }
    @MainActor func testSkipAbandonFutureAndInvalidFinishNeverEarnAnAward() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        var skipped = completed(25); skipped.status = .skipped
        var abandoned = completed(25); abandoned.status = .abandoned
        var invalid = completed(25); invalid.startedAt = date(26)
        store.update(sessions: [skipped, abandoned, completed(26), invalid], now: date(25, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
    }
    @MainActor func testFinishDateAcrossMidnightEarnsTheNewDay() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let start = date(24, hour: 23), end = date(25, hour: 1)
        var overnight = WorkoutSession(title: "Overnight", startedAt: start)
        let store = WorkoutStreakStore(defaults: prefs, sessions: [completed(24), overnight], now: start, calendar: calendar)
        overnight.status = .completed; overnight.endedAt = end
        store.update(sessions: [completed(24), overnight], now: end, calendar: calendar)
        XCTAssertEqual(store.pending?.day, calendar.startOfDay(for: end))
        XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 2)
    }
    @MainActor func testNewDayExpiresOldPendingAndNextCompletionCanCelebrate() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let store = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        store.update(sessions: [completed(25)], now: date(25, hour: 18), calendar: calendar)
        store.update(sessions: [completed(25)], now: date(26, hour: 8), calendar: calendar)
        XCTAssertNil(store.pending)
        store.update(sessions: [completed(25), completed(26)], now: date(26, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 2)
    }
    private func routine(rest weekdays: Set<Int>, startsOn: Date? = nil) -> Routine {
        var value = Routine(name: "Plan", isActive: true, createdAt: date(20), updatedAt: date(20), startsOn: startsOn)
        for index in value.days.indices { value.days[index].kind = weekdays.contains(index) ? .rest : .workout }
        return value
    }
    @MainActor func testRestPreservesCountWithoutCelebrationAndNextWorkoutEarnsTheNextCredit() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey); prefs.removeObject(forKey: WorkoutStreakStore.restStorageKey) }
        let sessions = [completed(23), completed(24)]
        let store = WorkoutStreakStore(defaults: prefs, sessions: sessions, routine: routine(rest: [6]), now: date(25), calendar: calendar)
        store.update(sessions: sessions, now: date(25), calendar: calendar)
        XCTAssertEqual(store.snapshot(sessions: sessions, now: date(25), calendar: calendar).consecutiveDays, 2)
        XCTAssertNil(store.pending)
        store.update(sessions: sessions + [completed(26)], now: date(26, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.previousCount, 2)
        XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 3)
        let id = try XCTUnwrap(store.pending?.id)
        store.acknowledge(id)
        store.update(sessions: sessions + [completed(26), completed(26)], now: date(26, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
    }
    @MainActor func testScheduleEditAndRelaunchPreservePastRestWithoutRetroactivelyExcusingMissedDays() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey); prefs.removeObject(forKey: WorkoutStreakStore.restStorageKey) }
        let sessions = [completed(23), completed(24)]
        let store = WorkoutStreakStore(defaults: prefs, sessions: sessions, routine: routine(rest: [6]), now: date(25), calendar: calendar)
        let noRest = routine(rest: [])
        store.updateRoutine(noRest, now: date(26), calendar: calendar)
        let restored = WorkoutStreakStore(defaults: prefs, sessions: sessions, routine: noRest, now: date(26), calendar: calendar)
        XCTAssertEqual(restored.snapshot(sessions: sessions, now: date(26), calendar: calendar).consecutiveDays, 2)
        XCTAssertTrue(WorkoutDayStreak.isRestDay(date(25), schedules: restored.restSchedules, calendar: calendar))
        XCTAssertFalse(WorkoutDayStreak.isRestDay(date(26), schedules: restored.restSchedules, calendar: calendar))
        // Monday was missed; setting Mondays to rest on Tuesday cannot rewrite it.
        restored.updateRoutine(routine(rest: [0]), now: date(27), calendar: calendar)
        XCTAssertEqual(restored.snapshot(sessions: sessions, now: date(27), calendar: calendar).consecutiveDays, 0)
        XCTAssertNil(restored.pending)
    }
    @MainActor func testOnlyActiveSavedRestDaysQualifyAndRoutineStartDateIsRespected() {
        let sessions = [completed(24)]
        var inactive = routine(rest: [6]); inactive.isActive = false
        var archived = routine(rest: [6]); archived.archivedAt = date(25)
        let flexible = routine(rest: [])
        for proposal in [inactive, archived, flexible, routine(rest: [6], startsOn: date(26))] {
            let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey); prefs.removeObject(forKey: WorkoutStreakStore.restStorageKey) }
            let store = WorkoutStreakStore(defaults: prefs, sessions: sessions, routine: proposal, now: date(26), calendar: calendar)
            XCTAssertEqual(store.snapshot(sessions: sessions, now: date(26), calendar: calendar).consecutiveDays, 0)
        }
    }
    @MainActor func testRestScheduleUpdatesAreIdempotentAndUndoRestoresTheProtectedPreviousCount() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey); prefs.removeObject(forKey: WorkoutStreakStore.restStorageKey) }
        let plan = routine(rest: [6]), sessions = [completed(24)]
        let store = WorkoutStreakStore(defaults: prefs, sessions: sessions, routine: plan, now: date(25), calendar: calendar)
        let baseline = store.restSchedules
        for _ in 0..<20 { store.updateRoutine(plan, now: date(26), calendar: calendar) }
        XCTAssertEqual(store.restSchedules, baseline)
        store.update(sessions: sessions + [completed(26)], now: date(26, hour: 18), calendar: calendar)
        XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 2)
        store.update(sessions: sessions, now: date(26, hour: 18), calendar: calendar)
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.snapshot(sessions: sessions, now: date(26), calendar: calendar).consecutiveDays, 1)
        // Repeated changes today replace one version, instead of growing forever.
        store.updateRoutine(routine(rest: [0, 6]), now: date(26), calendar: calendar)
        store.updateRoutine(plan, now: date(26), calendar: calendar)
        XCTAssertEqual(store.restSchedules.count, baseline.count + 1)
        XCTAssertNil(store.pending)
    }
    @MainActor func testDaylightSavingUsesCalendarDaysRatherThanTwentyFourHours() {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        var local = Calendar(identifier: .gregorian); local.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func localDate(_ day: Int) -> Date { local.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))! }
        let previous = WorkoutSession(title: "Before DST", startedAt: localDate(7).addingTimeInterval(-600), endedAt: localDate(7), status: .completed)
        let current = WorkoutSession(title: "After DST", startedAt: localDate(8).addingTimeInterval(-600), endedAt: localDate(8), status: .completed)
        let store = WorkoutStreakStore(defaults: prefs, sessions: [previous], now: localDate(7), calendar: local)
        store.update(sessions: [previous, current], now: localDate(8), calendar: local)
        XCTAssertEqual(store.pending?.snapshot.consecutiveDays, 2)
    }
    @MainActor func testMarkingPartialWorkoutDoneCreditsOnlyAfterFinishIsSaved() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let workouts = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let streaks = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        let observedNow = date(25, hour: 18), local = calendar
        workouts.onChange = { [weak workouts, weak streaks] in
            if let workouts { streaks?.update(sessions: workouts.sessions, now: observedNow, calendar: local) }
        }
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(), WorkoutSet()])])
        XCTAssertTrue(workouts.startQuickWorkout(draft, unit: .kg, now: date(25)))
        let id = try XCTUnwrap(workouts.active?.id)
        XCTAssertTrue(workouts.performFocused(.completeSet, sessionID: id, now: date(25).addingTimeInterval(10)))
        XCTAssertNil(streaks.pending) // A single set does not finish the whole workout.
        XCTAssertTrue(workouts.performFocused(.finish, sessionID: id, now: date(25).addingTimeInterval(20)))
        XCTAssertEqual(streaks.pending?.snapshot.consecutiveDays, 1)
        XCTAssertEqual(workouts.history.first?.remainingSetCount, 1)
    }

    @MainActor func testRealAutomaticCompletionAndFinishActionsNotifyOnlyAfterSuccessfulSave() throws {
        let prefs = defaults(); defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        let workouts = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let streaks = WorkoutStreakStore(defaults: prefs, sessions: [], now: date(25), calendar: calendar)
        let observedNow = date(25, hour: 18), local = calendar
        workouts.onChange = { [weak workouts, weak streaks] in
            if let workouts { streaks?.update(sessions: workouts.sessions, now: observedNow, calendar: local) }
        }
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(reps: 8, loadKG: 40)])])
        XCTAssertTrue(workouts.startQuickWorkout(draft, unit: .kg, now: date(25)))
        XCTAssertNil(streaks.pending)
        let id = try XCTUnwrap(workouts.active?.id)
        XCTAssertTrue(workouts.performFocused(.completeSet, sessionID: id, now: date(25).addingTimeInterval(30)))
        XCTAssertEqual(streaks.pending?.snapshot.consecutiveDays, 1)
        streaks.acknowledge(try XCTUnwrap(streaks.pending?.id))
        XCTAssertTrue(workouts.performFocused(.undo, sessionID: id, now: date(25).addingTimeInterval(40)))
        XCTAssertNil(streaks.pending)
        XCTAssertTrue(workouts.performFocused(.finish, sessionID: id, now: date(25).addingTimeInterval(50)))
        XCTAssertEqual(workouts.history.first?.status, .skipped)
        XCTAssertNil(streaks.pending)
    }
}
