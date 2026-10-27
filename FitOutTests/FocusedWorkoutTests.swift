import XCTest
@testable import FitOut

final class FocusedWorkoutTests: XCTestCase {
    @MainActor func testLiveRestShowsUpcomingSetAndNeverKeepsTheCompletedSetTimer() throws {
        var session = fixture(rest: 90)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(10))
        let state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(20))
        XCTAssertEqual(state.phase, "resting")
        XCTAssertEqual(state.setIndex, 2)
        XCTAssertEqual(state.exerciseIndex, 1)
        XCTAssertEqual(state.exerciseSetCount, 2)
        XCTAssertEqual(state.exerciseCount, 2)
        XCTAssertEqual(state.restStartedAt, at(10))
        XCTAssertNil(state.setTimerStart)
        XCTAssertNil(state.setTimerElapsed)
        XCTAssertTrue(state.target.hasPrefix("Set 2/2"))
        let display = WorkoutLivePresentation(state: state, now: at(20))
        XCTAssertEqual(display.status, "Rest")
        XCTAssertEqual(display.primaryTitle, "Skip rest")
        XCTAssertEqual(display.primaryAction, .endRest)
        XCTAssertFalse(display.setTimerVisible)
    }
    @MainActor func testLiveRestBetweenExercisesProjectsTheNextExerciseAndItsOwnFirstSet() throws {
        var session = fixture(rest: 90)
        session.entries[0].sets = [session.entries[0].sets[0]]
        WorkoutExecutionEngine.prepare(&session, at: at(0))
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(10))
        let state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(20))
        XCTAssertEqual(state.exercise, session.entries[1].exercise.name)
        XCTAssertEqual(state.exerciseIndex, 2)
        XCTAssertEqual(state.setIndex, 1)
        XCTAssertEqual(state.exerciseSetCount, session.entries[1].sets.count)
        XCTAssertEqual(WorkoutLivePresentation(state: state, now: at(20)).exerciseProgress, "2/2")
    }
    @MainActor func testExpiredOrStaleRestOffersContinueRatherThanExtendingAnExpiredTimer() throws {
        var session = fixture(rest: 90)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(10))
        let state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(20))
        for display in [WorkoutLivePresentation(state: state, stale: true, now: at(20)), WorkoutLivePresentation(state: state, now: at(101))] {
            XCTAssertTrue(display.restFinished)
            XCTAssertEqual(display.status, "Rest finished")
            XCTAssertEqual(display.primaryTitle, "Continue")
            XCTAssertEqual(display.primaryAction, .endRest)
        }
        // The existing end-rest command also remains safe after the deadline.
        try WorkoutExecutionEngine.apply(.skipRest, to: &session, at: at(101))
        XCTAssertEqual(session.execution?.phase, .ready)
        XCTAssertEqual(session.execution?.setID, session.entries[0].sets[1].id)
    }
    @MainActor func testPausedRestKeepsFrozenRemainingAndResumeActionWithoutSetTimer() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var session = fixture(rest: 90)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(10))
        XCTAssertTrue(store.save(session, at: at(10)))
        XCTAssertTrue(store.pause(now: at(20)))
        let paused = try XCTUnwrap(store.active)
        let state = WorkoutPresentationCoordinator.content(for: paused, unit: .kg, now: at(200))
        XCTAssertEqual(state.pausedRest, 80)
        XCTAssertEqual(state.setIndex, 2)
        XCTAssertNil(state.setTimerElapsed)
        let display = WorkoutLivePresentation(state: state, stale: true, now: at(200))
        XCTAssertEqual(display.status, "Rest paused")
        XCTAssertFalse(display.restFinished)
        XCTAssertEqual(display.primaryAction, .open)
    }
    @MainActor func testLiveProjectionAddsSafeUnicodeProgressAndOlderPayloadsStillDecode() throws {
        var session = fixture(rest: 0)
        session.title = String(repeating: "🏋🏽‍♂️", count: 100)
        session.entries[0].exercise.name = String(repeating: "👩🏽‍🚀", count: 100)
        let state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(1))
        XCTAssertFalse(state.title.contains("\u{FFFD}"))
        XCTAssertFalse(state.exercise.contains("\u{FFFD}"))
        XCTAssertLessThanOrEqual(state.title.utf8.count, 160)
        let data = try JSONEncoder().encode(state)
        XCTAssertLessThan(data.count, 4096)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["exerciseIndex", "exerciseCount", "setIndex", "exerciseSetCount", "prescription", "restStartedAt"] { old.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(WorkoutLiveAttributes.ContentState.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.exerciseIndex)
        XCTAssertFalse(WorkoutLivePresentation(state: decoded, now: at(1)).setProgress.isEmpty)
        XCTAssertEqual(WorkoutLivePresentation(state: decoded, now: at(1)).secondaryDetail, state.target)
    }
    @MainActor func testLiveReadyActiveTransitionAndEmptyActionsAreUnambiguous() throws {
        var session = fixture(rest: 0)
        var state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(1))
        XCTAssertEqual(WorkoutLivePresentation(state: state, now: at(1)).primaryAction, .startSet)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(3))
        XCTAssertEqual(WorkoutLivePresentation(state: state, now: at(3)).status, "In set")
        XCTAssertTrue(WorkoutLivePresentation(state: state, now: at(3)).setTimerVisible)
        XCTAssertEqual(WorkoutLivePresentation(state: state, now: at(3)).primaryAction, .open)
        state.phase = "exerciseTransition"
        XCTAssertEqual(WorkoutLivePresentation(state: state).primaryTitle, "Start exercise")
        state.totalSets = 0; state.loggedSets = 0; state.phase = "ready"
        XCTAssertEqual(WorkoutLivePresentation(state: state).status, "Set up workout")
        XCTAssertEqual(WorkoutLivePresentation(state: state).primaryAction, .open)
    }
    func testLiveClockFormattingBoundsInvalidAndLongDurations() {
        XCTAssertEqual(WorkoutLivePresentation.clock(65), "01:05")
        XCTAssertEqual(WorkoutLivePresentation.clock(3601), "1:00:01")
        XCTAssertEqual(WorkoutLivePresentation.clock(3601, compact: true), "1h")
        XCTAssertEqual(WorkoutLivePresentation.clock(-1), "00:00")
        XCTAssertEqual(WorkoutLivePresentation.clock(.nan), "00:00")
        XCTAssertEqual(WorkoutLivePresentation.clock(.infinity), "00:00")
    }
    @MainActor func testLiveProjectionShowsCurrentSetAndPersistedWeightUnitWithoutLaps() throws {
        var session = fixture(rest: 0)
        try WorkoutExecutionEngine.apply(.skipSet, to: &session, at: at(1))
        session.execution?.preferredUnit = .lbs
        let state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: at(2))
        XCTAssertTrue(state.target.hasPrefix("Set 2/2"))
        XCTAssertTrue(state.target.contains("lbs"))
        XCTAssertEqual(state.skippedSets, 1)
        XCTAssertEqual(state.phase, WorkoutPhase.ready.rawValue)
        XCTAssertNil(state.lastLap)
    }
    func testUndoStopsAStartedFollowingSetBeforeRewinding() throws {
        var session = fixture(rest: 0)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(10))
        let second = session.execution?.setID
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(11))
        try WorkoutExecutionEngine.apply(.undo, to: &session, at: at(20))
        XCTAssertEqual(session.execution?.setID, session.entries[0].sets[0].id)
        XCTAssertEqual(session.execution?.phase, .ready)
        XCTAssertEqual(session.entries[0].sets.first { $0.id == second }?.timedActiveSeconds, 9)
        XCTAssertEqual(session.completedSets.count, 0)
    }
    @MainActor func testDiskRecoveryKeepsSkippedActualAndPausedTransitionRecords() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("focused.store")
        var snapshot = fixture(); WorkoutExecutionEngine.prepare(&snapshot, at: start); snapshot.execution?.preferredUnit = .lbs
        let id = snapshot.id, first = snapshot.entries[0].sets[0].id, second = snapshot.entries[0].sets[1].id, last = snapshot.entries[1].sets[0].id
        do {
            let store = try WorkoutStore(container: PersistenceFactory.makeContainer(at: url))
            XCTAssertTrue(store.save(snapshot, at: start))
            store.performFocused(.startSet, sessionID: id, expectedSet: first, now: at(1))
            store.performFocused(.completeSet, sessionID: id, expectedSet: first, now: at(10))
            store.performFocused(.skipRest, sessionID: id, now: at(11))
            store.performFocused(.skipSet, sessionID: id, expectedSet: second, now: at(12))
            store.pause(now: at(13))
        }
        let reopened = try WorkoutStore(container: PersistenceFactory.makeContainer(at: url))
        XCTAssertEqual(reopened.active?.execution?.phase, .paused)
        XCTAssertEqual(reopened.active?.execution?.resumePhase, .exerciseTransition)
        XCTAssertEqual(reopened.active?.execution?.setID, last)
        XCTAssertEqual(reopened.active?.execution?.preferredUnit, .lbs)
        XCTAssertEqual(reopened.active?.entries[0].sets[0].actual?.seconds, 9)
        XCTAssertEqual(reopened.active?.entries[0].sets[1].status, .skipped)
        XCTAssertNil(reopened.active?.entries[0].sets[1].completedAt)
        reopened.resume(now: at(30))
        reopened.performFocused(.startSet, sessionID: id, expectedSet: last, now: at(31))
        reopened.performFocused(.completeSet, sessionID: id, expectedSet: last, now: at(40))
        XCTAssertEqual(reopened.history.first?.volumeKG, 560)
        XCTAssertEqual(reopened.history.first?.duration(), 23)
        XCTAssertEqual(reopened.history.first?.skippedSets.count, 1)
    }

    @MainActor func testFinishDiscardAndUndoCannotOverwriteAnotherActiveWorkout() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var session = fixture(); WorkoutExecutionEngine.prepare(&session, at: start)
        XCTAssertTrue(store.save(session, at: start))
        store.performFocused(.startSet, sessionID: session.id, now: at(1))
        store.performFocused(.completeSet, sessionID: session.id, now: at(10))
        store.pause(now: at(11))
        store.performFocused(.finish, sessionID: session.id, now: at(20))
        XCTAssertEqual(store.history.first?.duration(), 11)
        XCTAssertEqual(store.history.first?.remainingSetCount, 2)
        XCTAssertTrue(store.start(catalogue: [], now: at(21)))
        let other = try XCTUnwrap(store.active?.id)
        XCTAssertFalse(store.performFocused(.undo, sessionID: session.id, now: at(22)))
        XCTAssertEqual(store.active?.id, other)
        XCTAssertTrue(store.delete(other)); XCTAssertNil(store.active)
        XCTAssertTrue(store.performFocused(.undo, sessionID: session.id, now: at(23)))
        XCTAssertEqual(store.active?.id, session.id); XCTAssertEqual(store.active?.execution?.phase, .ready)
        XCTAssertEqual(store.active?.completedSets.count, 0)
    }

    @MainActor func testStaleAndRepeatedLiveRestCommandsCannotChangeNewRest() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var session = fixture(); WorkoutExecutionEngine.prepare(&session, at: start)
        XCTAssertTrue(store.save(session, at: start))
        let stale = try XCTUnwrap(store.active?.telemetry?.revision)
        store.performFocused(.startSet, sessionID: session.id, now: at(1))
        store.performFocused(.completeSet, sessionID: session.id, now: at(10))
        XCTAssertTrue(store.runQuickAction("endRest", sessionID: session.id, commandID: stale, now: at(11)))
        XCTAssertEqual(store.active?.restUntil, at(40))
        let revision = try XCTUnwrap(store.active?.telemetry?.revision)
        XCTAssertTrue(store.runQuickAction("extendRest", sessionID: session.id, commandID: revision, now: at(12)))
        XCTAssertTrue(store.runQuickAction("extendRest", sessionID: session.id, commandID: revision, now: at(13)))
        XCTAssertEqual(store.active?.restUntil, at(55))
    }

    func testStageUsesElapsedTimeAndOnlyTimedExerciseTargetsForArc() throws {
        var session = fixture()
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        let weighted = WorkoutStageTiming(session: session, entry: session.entries[0], set: session.entries[0].sets[0], now: at(11))
        XCTAssertEqual(weighted.seconds, 10)
        XCTAssertEqual(weighted.progress, 0) // A rep-based set has no invented time limit.
        XCTAssertEqual(weighted.title, "Set time")
        XCTAssertEqual(weighted.detail, "0/3 sets logged")
        session.entries[0].exercise.kind = .duration
        session.entries[0].sets[0].seconds = 20
        let timed = WorkoutStageTiming(session: session, entry: session.entries[0], set: session.entries[0].sets[0], now: at(11))
        XCTAssertEqual(timed.progress, 0.5)
        XCTAssertEqual(timed.detail, "Target · 00:20")
        session.entries[0].sets[0].seconds = 40
        XCTAssertEqual(WorkoutStageTiming(session: session, entry: session.entries[0], set: session.entries[0].sets[0], now: at(11)).progress, 0.25)
        XCTAssertEqual(WorkoutStageTiming(session: session, entry: session.entries[0], set: session.entries[0].sets[0], now: at(100)).progress, 1)
    }

    @MainActor func testStageRestBudgetIncludesExtensionAndFreezesWhilePaused() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var value = fixture(); WorkoutExecutionEngine.prepare(&value, at: start)
        XCTAssertTrue(store.save(value, at: start))
        store.performFocused(.startSet, sessionID: value.id, now: at(1))
        store.performFocused(.completeSet, sessionID: value.id, now: at(10))
        func timing(at seconds: Double) throws -> WorkoutStageTiming {
            let session = try XCTUnwrap(store.active)
            let current = try XCTUnwrap(session.executingWork)
            return WorkoutStageTiming(session: session, entry: current.entry, set: current.set, now: at(seconds))
        }
        XCTAssertEqual(try timing(at: 20).seconds, 20)
        XCTAssertEqual(try timing(at: 20).progress, 20.0 / 30, accuracy: 0.001)
        store.performFocused(.extendRest, sessionID: value.id, now: at(20))
        XCTAssertEqual(try timing(at: 20).seconds, 35)
        XCTAssertEqual(try timing(at: 20).progress, 35.0 / 45, accuracy: 0.001)
        store.pause(now: at(25))
        XCTAssertEqual(try timing(at: 100).seconds, 30)
        XCTAssertEqual(try timing(at: 100).progress, 30.0 / 45, accuracy: 0.001)
        XCTAssertEqual(try timing(at: 100).title, "Rest paused")
        XCTAssertTrue(try timing(at: 100).isResting)
        XCTAssertEqual(try timing(at: 100).detail, "Last set · 00:09")
    }

    @MainActor func testStageActiveSetClockFreezesWhenPaused() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var value = fixture(); WorkoutExecutionEngine.prepare(&value, at: start)
        XCTAssertTrue(store.save(value, at: start))
        store.performFocused(.startSet, sessionID: value.id, now: at(1)); store.pause(now: at(6))
        let session = try XCTUnwrap(store.active), current = try XCTUnwrap(store.active?.executingWork)
        let timing = WorkoutStageTiming(session: session, entry: current.entry, set: current.set, now: at(100))
        XCTAssertEqual(timing.seconds, 5); XCTAssertEqual(timing.title, "Set paused")
        XCTAssertFalse(timing.isResting)
    }

    func testStageDistinguishesSkippedProgressFromLoggedSets() throws {
        var session = fixture()
        try WorkoutExecutionEngine.apply(.skipSet, to: &session, at: at(1))
        let current = try XCTUnwrap(session.executingWork)
        let timing = WorkoutStageTiming(session: session, entry: current.entry, set: current.set, now: at(100))
        XCTAssertEqual(timing.title, "Ready to start"); XCTAssertEqual(timing.seconds, 0)
        XCTAssertEqual(timing.progress, 1.0 / 3, accuracy: 0.001)
        XCTAssertEqual(timing.detail, "0 logged · 1 skipped")
        XCTAssertEqual(session.completedSets.count, 0); XCTAssertEqual(session.volumeKG, 0)
    }

    func testBottomPreviewFollowsNextSetExerciseAndFinalSummaryWithoutAdvancing() throws {
        var session = fixture(rest: 0); WorkoutExecutionEngine.prepare(&session, at: start)
        let firstName = session.entries[0].exercise.name, secondName = session.entries[1].exercise.name
        XCTAssertEqual(WorkoutActionPreview(session: session).detail, firstName + " · Set 1 of 2")
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        let before = session
        XCTAssertEqual(WorkoutActionPreview(session: session).detail, "Next · " + firstName + " · Set 2 of 2")
        XCTAssertEqual(session, before)
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(2))
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(3))
        XCTAssertEqual(WorkoutActionPreview(session: session).detail, "Next · " + secondName + " · Set 1 of 1")
        try WorkoutExecutionEngine.apply(.skipSet, to: &session, at: at(4))
        XCTAssertEqual(WorkoutActionPreview(session: session).detail, secondName + " · Set 1 of 1")
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(5))
        XCTAssertEqual(WorkoutActionPreview(session: session).detail, "Final set · Workout summary follows")
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(6))
        XCTAssertNil(WorkoutActionPreview(session: session).detail)
    }

    private let start = Date(timeIntervalSince1970: 200_000)
    private func fixture(rest: Int = 30) -> WorkoutSession {
        WorkoutSession(title: "Focused", startedAt: start, entries: [
            WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(reps: 8, loadKG: 40), WorkoutSet(reps: 10, loadKG: 45)], restSeconds: rest),
            WorkoutEntry(exercise: ExerciseCatalogue.all[1], sets: [WorkoutSet(reps: 12, loadKG: 20)], restSeconds: rest)])
    }
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    func testOrderedReadySetRestTransitionAndFinalSummary() throws {
        var session = fixture()
        WorkoutExecutionEngine.prepare(&session, at: start)
        let first = session.entries[0].sets[0].id, second = session.entries[0].sets[1].id, last = session.entries[1].sets[0].id
        XCTAssertEqual(session.execution?.phase, .ready); XCTAssertEqual(session.execution?.setID, first)
        XCTAssertTrue(try WorkoutExecutionEngine.apply(.startSet, to: &session, expectedSet: first, at: at(5)))
        XCTAssertEqual(session.execution?.phase, .activeSet)
        XCTAssertTrue(try WorkoutExecutionEngine.apply(.completeSet, to: &session, expectedSet: first, at: at(20)))
        XCTAssertEqual(session.entries[0].sets[0].actual?.seconds, 15)
        XCTAssertEqual(session.entries[0].sets[0].actual?.reps, 8)
        XCTAssertEqual(session.execution?.phase, .resting); XCTAssertEqual(session.restUntil, at(50))
        XCTAssertTrue(try WorkoutExecutionEngine.apply(.extendRest, to: &session, at: at(25)))
        XCTAssertEqual(session.restUntil, at(65))
        WorkoutExecutionEngine.prepare(&session, at: at(65))
        XCTAssertEqual(session.execution?.phase, .ready); XCTAssertEqual(session.execution?.setID, second)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, expectedSet: second, at: at(70))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, expectedSet: second, at: at(85))
        try WorkoutExecutionEngine.apply(.skipRest, to: &session, at: at(86))
        XCTAssertEqual(session.execution?.phase, .exerciseTransition)
        XCTAssertEqual(session.execution?.entryID, session.entries[1].id)
        try WorkoutExecutionEngine.apply(.startSet, to: &session, expectedSet: last, at: at(90))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, expectedSet: last, at: at(105))
        XCTAssertEqual(session.execution?.phase, .workoutCompleted); XCTAssertEqual(session.status, .completed)
        XCTAssertNil(session.restUntil); XCTAssertEqual(session.endedAt, at(105))
        XCTAssertEqual(session.completedSets.count, 3); XCTAssertEqual(session.skippedSets.count, 0)
        XCTAssertEqual(session.volumeKG, 1010)
    }

    func testDuplicateAndStaleSetActionsDoNotLogOrAdvanceTwice() throws {
        var session = fixture(rest: 0)
        WorkoutExecutionEngine.prepare(&session, at: start)
        let first = session.entries[0].sets[0].id
        try WorkoutExecutionEngine.apply(.startSet, to: &session, expectedSet: first, at: at(1))
        XCTAssertFalse(try WorkoutExecutionEngine.apply(.startSet, to: &session, expectedSet: first, at: at(2)))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, expectedSet: first, at: at(10))
        let next = session.execution?.setID
        XCTAssertFalse(try WorkoutExecutionEngine.apply(.completeSet, to: &session, expectedSet: first, at: at(11)))
        XCTAssertFalse(try WorkoutExecutionEngine.apply(.skipSet, to: &session, expectedSet: first, at: at(12)))
        XCTAssertEqual(session.completedSets.count, 1); XCTAssertEqual(session.execution?.setID, next)
    }

    func testSkippingAndUndoNeverFabricateCompletionOrVolume() throws {
        var session = fixture(rest: 0)
        WorkoutExecutionEngine.prepare(&session, at: start)
        let first = session.entries[0].sets[0].id
        try WorkoutExecutionEngine.apply(.skipSet, to: &session, expectedSet: first, at: at(2))
        XCTAssertEqual(session.skippedSets.count, 1); XCTAssertEqual(session.volumeKG, 0)
        XCTAssertNil(session.entries[0].sets[0].completedAt); XCTAssertNil(session.entries[0].sets[0].actual)
        XCTAssertEqual(session.setProgress, 1.0 / 3.0, accuracy: 0.001)
        try WorkoutExecutionEngine.apply(.undo, to: &session, at: at(3))
        XCTAssertEqual(session.execution?.setID, first); XCTAssertEqual(session.execution?.phase, .ready)
        XCTAssertTrue(session.skippedSets.isEmpty); XCTAssertNil(session.execution?.undo)
        XCTAssertNil(session.entries[0].sets[0].startedAt)
    }

    func testAllSkippedEndsAsSkippedAndCanBeRecoveredWithUndo() throws {
        var session = fixture(rest: 0)
        WorkoutExecutionEngine.prepare(&session, at: start)
        for index in 0..<3 { try WorkoutExecutionEngine.apply(.skipSet, to: &session, expectedSet: session.execution?.setID, at: at(Double(index + 1))) }
        XCTAssertEqual(session.status, .skipped); XCTAssertEqual(session.execution?.phase, .workoutCompleted)
        XCTAssertEqual(session.skippedSets.count, 3); XCTAssertTrue(session.completedSets.isEmpty); XCTAssertEqual(session.volumeKG, 0)
        let duration = session.duration()
        try WorkoutExecutionEngine.apply(.undo, to: &session, at: at(20))
        XCTAssertEqual(session.status, .inProgress); XCTAssertEqual(session.skippedSets.count, 2)
        XCTAssertEqual(session.duration(at: at(20)), duration, accuracy: 0.001)
    }

    func testMeasuredDurationAndPlannedTargetsRemainSeparate() throws {
        let exercise = try XCTUnwrap(ExerciseCatalogue.all.first { $0.kind == .duration })
        let target = PlannedSet(seconds: 30)
        var session = WorkoutSession(title: "Timed", startedAt: start, entries: [WorkoutEntry(exercise: exercise, sets: [WorkoutSet(seconds: 30, plannedTarget: target)])])
        try WorkoutExecutionEngine.apply(.startSet, to: &session, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &session, at: at(36))
        let set = session.entries[0].sets[0]
        XCTAssertEqual(set.seconds, 35); XCTAssertEqual(set.actual?.seconds, 35)
        XCTAssertEqual(set.plannedTarget?.seconds, 30); XCTAssertEqual(set.inputTarget?.seconds, 30)
        XCTAssertEqual(session.volumeKG, 0)
    }

    @MainActor func testPauseResumePersistsActiveSetAndRestAcrossReload() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try WorkoutStore(container: database)
        var snapshot = fixture(); WorkoutExecutionEngine.prepare(&snapshot, at: start)
        XCTAssertTrue(store.save(snapshot, at: start))
        let id = snapshot.id, first = snapshot.entries[0].sets[0].id
        store.performFocused(.startSet, sessionID: id, expectedSet: first, now: at(5))
        store.pause(now: at(15)); XCTAssertEqual(store.active?.execution?.phase, .paused)
        let reopened = try WorkoutStore(container: database)
        reopened.resume(now: at(35)); XCTAssertEqual(reopened.active?.execution?.phase, .activeSet)
        reopened.performFocused(.completeSet, sessionID: id, expectedSet: first, now: at(45))
        XCTAssertEqual(reopened.active?.entries[0].sets[0].actual?.seconds, 20)
        XCTAssertEqual(reopened.active?.restUntil, at(75))
        reopened.pause(now: at(55)); reopened.resume(now: at(155))
        XCTAssertEqual(reopened.active?.restUntil, at(175))
        XCTAssertEqual(reopened.active?.restRemaining(at: at(155)), 20)
        let recovered = try WorkoutStore(container: database)
        recovered.prepareFocusedSession(id, now: at(176))
        XCTAssertEqual(recovered.active?.execution?.phase, .ready)
        XCTAssertEqual(recovered.active?.execution?.setID, snapshot.entries[0].sets[1].id)
        XCTAssertEqual(recovered.active?.completedSets.count, 1)
    }

    @MainActor func testImmediateSaveIdempotenceAndUndoAfterFinishing() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try WorkoutStore(container: database)
        var snapshot = fixture(rest: 0); snapshot.entries = [WorkoutEntry(exercise: snapshot.entries[0].exercise, sets: [snapshot.entries[0].sets[0]])]
        WorkoutExecutionEngine.prepare(&snapshot, at: start); XCTAssertTrue(store.save(snapshot, at: start))
        let setID = snapshot.entries[0].sets[0].id
        store.performFocused(.startSet, sessionID: snapshot.id, expectedSet: setID, now: at(1))
        var writes = 0; store.onChange = { writes += 1 }
        store.performFocused(.completeSet, sessionID: snapshot.id, expectedSet: setID, now: at(10))
        store.performFocused(.completeSet, sessionID: snapshot.id, expectedSet: setID, now: at(11))
        XCTAssertEqual(writes, 1)
        let reopened = try WorkoutStore(container: database)
        XCTAssertEqual(reopened.history.first?.completedSets.count, 1)
        XCTAssertEqual(reopened.history.first?.entries[0].sets[0].actual?.seconds, 9)
        XCTAssertTrue(reopened.performFocused(.undo, sessionID: snapshot.id, now: at(20)))
        XCTAssertEqual(reopened.active?.execution?.phase, .ready); XCTAssertEqual(reopened.active?.volumeKG, 0)
        XCTAssertEqual(reopened.active?.duration(at: at(20)), 10)
        XCTAssertTrue(reopened.history.isEmpty)
    }

    @MainActor func testEmptyValidationAndViewModelInvalidInputCannotCompleteSavedDefaults() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.start(catalogue: [], now: start))
        let id = try XCTUnwrap(store.active?.id)
        XCTAssertTrue(store.performFocused(.startSet, sessionID: id, now: at(1)))
        XCTAssertEqual(store.active?.completedSets.count, 0)
        store.add(ExerciseCatalogue.all[0])
        let model = FocusedWorkoutModel(store: store, unit: .kg)
        model.refresh()
        var set = try XCTUnwrap(model.current?.set)
        model.perform(.startSet, expectedSet: set.id)
        set.loadKG = .nan; model.editSet(set, field: .load)
        XCTAssertNotNil(model.inputError)
        model.perform(.completeSet, expectedSet: set.id)
        XCTAssertEqual(store.active?.completedSets.count, 0)
        set.loadKG = 40; model.editSet(set, field: .load)
        XCTAssertNil(model.inputError)
        set.reps = 0; model.editSet(set, field: .reps)
        model.perform(.completeSet, expectedSet: set.id)
        XCTAssertEqual(store.active?.completedSets.count, 0); XCTAssertNotNil(store.error)
        model.deactivate()
    }

    @MainActor func testObsoleteRestTaskCannotAdvancePausedSession() async throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let now = Date()
        var session = fixture(); session.startedAt = now.addingTimeInterval(-10)
        WorkoutExecutionEngine.prepare(&session, at: now)
        session.entries[0].sets[0].completedAt = now
        session.execution?.phase = .resting; session.restUntil = now.addingTimeInterval(0.1)
        XCTAssertTrue(store.save(session, at: now))
        let model = FocusedWorkoutModel(store: store, unit: .kg)
        model.activate(); model.togglePause()
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(store.active?.execution?.phase, .paused)
        XCTAssertEqual(store.active?.execution?.resumePhase, .resting)
        XCTAssertEqual(store.active?.execution?.setID, session.entries[0].sets[0].id)
        model.deactivate()
    }

    @MainActor func testRoutineSnapshotCannotBeRewrittenByLaterRoutineEdits() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var day = RoutineDay(weekday: 2, title: "Original", kind: .workout, exercises: [PlannedExercise(exerciseID: ExerciseCatalogue.all[0].id, loadKG: 45)])
        XCTAssertTrue(store.start(day: day, routineID: UUID(), catalogue: ExerciseCatalogue.all, now: start))
        day.title = "Changed"; day.exercises[0].loadKG = 100
        XCTAssertEqual(store.active?.title, "Original")
        XCTAssertEqual(store.active?.entries[0].sets[0].plannedTarget?.loadKG, 45)
        XCTAssertEqual(store.active?.execution?.phase, .ready)
    }
}
