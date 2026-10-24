import XCTest
@testable import FitOut

final class FocusedWorkoutTests: XCTestCase {
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
