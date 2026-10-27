import XCTest
@testable import FitOut

final class WorkoutSessionEditingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    private func session(rest: Int = 30) -> WorkoutSession {
        var value = WorkoutSession(title: "Six exercises", startedAt: start,
            entries: Array(ExerciseCatalogue.all.prefix(6)).map { WorkoutEntry(exercise: $0, sets: [WorkoutSet(reps: 8, loadKG: 40), WorkoutSet(reps: 10, loadKG: 45)], restSeconds: rest) })
        WorkoutExecutionEngine.prepare(&value, at: start)
        return value
    }
    func testReorderingReadySessionMakesSecondExerciseFirstWithoutChangingTargetsOrRecords() throws {
        var value = session()
        let originals = value.entries, second = originals[1].id
        let ids = [second, originals[0].id] + originals.dropFirst(2).map(\.id)
        try WorkoutSessionEditing.apply(.reorder(ids), to: &value, history: [], at: at(2))
        XCTAssertEqual(value.entries.map(\.id), ids)
        XCTAssertEqual(value.execution?.entryID, second)
        XCTAssertEqual(value.entries[0], originals[1])
        XCTAssertEqual(value.completedSets.count, 0)
        XCTAssertTrue(value.isActive)
    }
    func testReorderPreservesRunningSetAndSubsequentRestUsesTheNewQueue() throws {
        var value = session(rest: 10)
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        let current = value.execution?.setID, first = value.entries[0].id, second = value.entries[1].id
        let ids = [second, first] + value.entries.dropFirst(2).map(\.id)
        try WorkoutSessionEditing.apply(.reorder(ids), to: &value, history: [], at: at(5))
        XCTAssertEqual(value.execution?.setID, current)
        XCTAssertEqual(value.execution?.phase, .activeSet)
        XCTAssertEqual(value.setElapsed(value.executingWork!.set, at: at(5)), 4)
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(8))
        let deadline = value.restUntil
        try WorkoutSessionEditing.apply(.reorder(ids), to: &value, history: [], at: at(10))
        XCTAssertEqual(value.restUntil, deadline)
        WorkoutExecutionEngine.prepare(&value, at: at(19))
        XCTAssertEqual(value.execution?.entryID, second)
    }
    func testDoNextFreezesOldTimerAndReturningAccumulatesOnlyActiveSetTime() throws {
        var value = session(rest: 0)
        let original = value.entries[0], second = value.entries[1]
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutSessionEditing.apply(.focus(second.id), to: &value, history: [], at: at(11))
        XCTAssertEqual(value.entries.first?.id, second.id)
        XCTAssertEqual(value.execution?.entryID, second.id)
        XCTAssertEqual(value.entries.first { $0.id == original.id }?.sets[0].timedActiveSeconds, 10)
        XCTAssertTrue(value.completedSets.isEmpty)
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(12))
        try WorkoutSessionEditing.apply(.focus(original.id), to: &value, history: [], at: at(20))
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(30))
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(35))
        XCTAssertEqual(value.entries.first { $0.id == original.id }?.sets[0].actual?.seconds, 15)
        XCTAssertEqual(value.entries.first { $0.id == second.id }?.sets[0].timedActiveSeconds, 8)
    }
    func testSwitchingPausedRestKeepsPauseAndNeverStartsSelectedSetAutomatically() throws {
        var value = session()
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(5))
        value.status = .paused; value.pausedAt = at(10); value.execution?.resumePhase = .resting; value.execution?.phase = .paused
        let second = value.entries[1]
        try WorkoutSessionEditing.apply(.focus(second.id), to: &value, history: [], at: at(20))
        XCTAssertEqual(value.status, .paused)
        XCTAssertEqual(value.pausedAt, at(10))
        XCTAssertEqual(value.execution?.phase, .paused)
        XCTAssertEqual(value.execution?.resumePhase, .exerciseTransition)
        XCTAssertNil(value.restUntil)
        XCTAssertNil(value.executingWork?.set.startedAt)
    }
    func testSkippingFutureExerciseNeverStopsCurrentTimerAndNeverAddsVolume() throws {
        var value = session()
        let current = value.entries[0].id, second = value.entries[1].id
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutSessionEditing.apply(.skip(second), to: &value, history: [], at: at(5))
        XCTAssertEqual(value.execution?.entryID, current)
        XCTAssertEqual(value.execution?.phase, .activeSet)
        XCTAssertNil(value.executingWork?.set.timedActiveSeconds)
        XCTAssertEqual(value.setElapsed(value.executingWork!.set, at: at(10)), 9)
        XCTAssertEqual(value.skippedSets.count, 2)
        XCTAssertEqual(value.volumeKG, 0)
        XCTAssertTrue(value.entries.first { $0.id == second }!.sets.allSatisfy { $0.completedAt == nil && $0.actual == nil })
    }
    func testSkippingCurrentPartialExerciseKeepsActualsAndAdvancesSafely() throws {
        var value = session(rest: 0)
        let original = value.entries[0].id
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(5))
        let completed = value.completedSets[0]
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(6))
        try WorkoutSessionEditing.apply(.skip(original), to: &value, history: [], at: at(10))
        XCTAssertNotEqual(value.execution?.entryID, original)
        XCTAssertEqual(value.entries[0].sets[0], completed)
        XCTAssertEqual(value.entries[0].sets[1].timedActiveSeconds, 4)
        XCTAssertEqual(value.entries[0].sets[1].status, .skipped)
        XCTAssertEqual(value.completedSets.count, 1)
        XCTAssertEqual(value.volumeKG, 320)
    }
    func testRemovingExerciseKeepsRecordedSetsAndLeavesEmptySessionForExplicitFinish() throws {
        var value = session(rest: 0)
        value.entries = [value.entries[0]]
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(5))
        let done = value.completedSets
        try WorkoutSessionEditing.apply(.remove(value.entries[0].id), to: &value, history: [], at: at(8))
        XCTAssertEqual(value.entries[0].sets, done)
        XCTAssertNil(value.execution?.setID)
        XCTAssertTrue(value.isActive)
        XCTAssertEqual(value.volumeKG, 320)
        var empty = session(); empty.entries = [empty.entries[0]]
        try WorkoutSessionEditing.apply(.remove(empty.entries[0].id), to: &empty, history: [], at: at(2))
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertTrue(empty.isActive)
    }
    func testReplacementUsesItsOwnRecallAndPreservesEarlierExerciseActuals() throws {
        var value = session(rest: 0)
        let original = value.entries[0]
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(5))
        let done = value.completedSets[0]
        let replacement = ExerciseCatalogue.byID["curl"]!
        let history = WorkoutSession(title: "Earlier", startedAt: start.addingTimeInterval(-1000), endedAt: start.addingTimeInterval(-900), status: .completed,
            entries: [WorkoutEntry(exercise: replacement, sets: [WorkoutSet(reps: 12, loadKG: 16, completedAt: start.addingTimeInterval(-900))])])
        try WorkoutSessionEditing.apply(.replace(original.id, replacement), to: &value, history: [history], at: at(6))
        XCTAssertEqual(value.entries[0].exercise, original.exercise)
        XCTAssertEqual(value.entries[0].sets, [done])
        XCTAssertEqual(value.entries[1].exercise, replacement)
        XCTAssertEqual(value.entries[1].sets[0].loadKG, 16)
        XCTAssertEqual(value.entries[1].sets[0].reps, 12)
        XCTAssertNotEqual(value.entries[1].id, original.id)
        XCTAssertEqual(value.execution?.entryID, value.entries[1].id)
        XCTAssertNil(value.entries[1].sets[0].startedAt)
        XCTAssertEqual(value.volumeKG, 320)
    }
    func testReplacingUnloggedExerciseChangesOnlyThatSnapshotAndCreatesFreshSetIDs() throws {
        var value = session()
        let original = value.entries[0], other = value.entries[1], replacement = ExerciseCatalogue.byID["plank"]!
        try WorkoutSessionEditing.apply(.replace(original.id, replacement), to: &value, history: [], at: at(2))
        XCTAssertEqual(value.entries.count, 6)
        XCTAssertEqual(value.entries[0].id, original.id)
        XCTAssertEqual(value.entries[0].exercise, replacement)
        XCTAssertTrue(Set(value.entries[0].sets.map(\.id)).isDisjoint(with: Set(original.sets.map(\.id))))
        XCTAssertTrue(value.entries[0].sets.allSatisfy { $0.seconds > 0 && $0.actual == nil && $0.startedAt == nil })
        XCTAssertEqual(value.entries[1], other)
    }
    func testStaleReorderAndFinishedSessionAreRejectedWithoutSavingPartialEdits() throws {
        var value = session()
        let original = value
        XCTAssertThrowsError(try WorkoutSessionEditing.apply(.reorder(Array(value.entries.dropFirst().map(\.id))), to: &value, history: [], at: at(1)))
        XCTAssertEqual(value, original)
        value.status = .completed
        XCTAssertThrowsError(try WorkoutSessionEditing.apply(.remove(value.entries[0].id), to: &value, history: [], at: at(2)))
    }
    func testReplacingTimedMovementWithWeightedMovementGetsUsableRepDefaults() throws {
        var value = session()
        value.entries[0].exercise = ExerciseCatalogue.byID["plank"]!
        value.entries[0].sets = [WorkoutSet(reps: 0, seconds: 30)]
        try WorkoutSessionEditing.apply(.replace(value.entries[0].id, ExerciseCatalogue.byID["curl"]!), to: &value, history: [], at: at(2))
        XCTAssertEqual(value.entries[0].sets[0].reps, 8)
        XCTAssertEqual(value.entries[0].sets[0].seconds, 0)
        XCTAssertNil(value.entries[0].sets[0].actual)
    }
    @MainActor func testDiskReopenRetainsOrderFocusSkippedSetsAndOriginalSavedRoutine() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SessionEditing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("store")
        var expected: WorkoutSession!
        var saved: Routine!
        do {
            let database = try PersistenceFactory.makeContainer(at: url), store = try WorkoutStore(container: database), gym = try GymStore(container: database)
            let routine = RoutineTemplate.fullBody.make()
            XCTAssertTrue(gym.save(routine)); saved = gym.activeRoutine!
            XCTAssertTrue(store.start(day: saved.days[0], routineID: saved.id, catalogue: gym.exercises, now: start))
            let current = try XCTUnwrap(store.active)
            XCTAssertTrue(store.editSession(.focus(current.entries[1].id), sessionID: current.id, now: at(2)))
            XCTAssertTrue(store.editSession(.skip(current.entries[2].id), sessionID: current.id, now: at(3)))
            expected = store.active
            XCTAssertEqual(gym.activeRoutine, saved)
            XCTAssertTrue(expected.telemetry?.events.contains { $0.kind == .exercisesReordered } == true)
        }
        let reopened = try PersistenceFactory.makeContainer(at: url)
        XCTAssertEqual(try WorkoutStore(container: reopened).active, expected)
        XCTAssertEqual(try GymStore(container: reopened).activeRoutine, saved)
    }
    func testWheelTicksFractionalWeightsBoundsAndExactValueParsing() {
        let range = WorkoutWheelRange(minimum: 0, maximum: 1000, step: 0.5)
        XCTAssertEqual(range.count, 2001)
        XCTAssertEqual(range.number(at: 85), 42.5)
        XCTAssertEqual(range.tick(for: 42.5), 85)
        XCTAssertEqual(range.adjusted(42.27, direction: 1), 42.77)
        XCTAssertEqual(range.adjusted(0, direction: -1), 0)
        XCTAssertEqual(range.adjusted(1000, direction: 1), 1000)
        let reps = WorkoutWheelRange(minimum: 1, maximum: 1000, step: 1)
        XCTAssertEqual(reps.number(at: 0), 1)
        XCTAssertEqual(reps.number(at: 9), 10)
        XCTAssertEqual(WorkoutConfigurationValue.parse("42,27", maximum: 1000, integer: false, positive: false, decimalSeparator: ","), 42.27)
        XCTAssertNil(WorkoutConfigurationValue.parse("10.5", maximum: 1000, integer: true, positive: false))
    }
    @MainActor func testNumberPickerEditingBlocksCompletionAndLateEditsCannotChangeAnotherSet() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(session(rest: 0), at: start))
        let model = FocusedWorkoutModel(store: store, unit: .kg)
        model.activate(); model.perform(.startSet)
        model.editingInputs.insert(.load); model.perform(.completeSet)
        XCTAssertTrue(store.active!.completedSets.isEmpty)
        model.editingInputs.remove(.load)
        let old = try XCTUnwrap(model.current?.set), id = try XCTUnwrap(store.active?.id)
        XCTAssertTrue(store.editSession(.focus(store.active!.entries[1].id), sessionID: id))
        model.refresh()
        let current = try XCTUnwrap(model.current?.set)
        var stale = old; stale.loadKG = 999
        model.editSet(stale, field: .load)
        XCTAssertEqual(model.current?.set, current)
        XCTAssertTrue(model.editingInputs.isEmpty)
        model.deactivate()
    }
}
