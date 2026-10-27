import XCTest
@testable import FitOut

final class WorkoutRecordedSetTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    private func session(rest: Int = 30) throws -> WorkoutSession {
        var value = WorkoutSession(title: "Training", startedAt: start, entries: [
            WorkoutEntry(exercise: ExerciseCatalogue.byID["bench"]!,
                         sets: [WorkoutSet(reps: 8, loadKG: 40), WorkoutSet(reps: 10, loadKG: 45)], restSeconds: rest)
        ])
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(1))
        try WorkoutExecutionEngine.apply(.completeSet, to: &value, at: at(11))
        return value
    }
    private func changed(_ reference: WorkoutRecordedSet) -> WorkoutSet {
        var set = reference.original; set.loadKG = 52.5; set.reps = 12; set.rpe = 8; set.note = "Corrected result"
        return set
    }
    @MainActor func testCorrectionDuringRestKeepsProgressClocksTargetsAndPendingSets() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(try session(), at: at(11)))
        let before = try XCTUnwrap(store.active), ref = try XCTUnwrap(before.lastRecordedSet)
        XCTAssertTrue(store.correctRecordedSet(changed(ref), reference: ref, now: at(20)))
        let after = try XCTUnwrap(store.active), set = after.entries[0].sets[0]
        XCTAssertEqual(after.restUntil, before.restUntil)
        XCTAssertEqual(after.execution, before.execution)
        XCTAssertEqual(after.status, before.status)
        XCTAssertEqual(after.startedAt, before.startedAt)
        XCTAssertEqual(after.endedAt, before.endedAt)
        XCTAssertEqual(after.pausedSeconds, before.pausedSeconds)
        XCTAssertEqual(after.entries[0].sets[1], before.entries[0].sets[1])
        XCTAssertEqual(set.completedAt, ref.original.completedAt)
        XCTAssertEqual(set.startedAt, ref.original.startedAt)
        XCTAssertEqual(set.startedActiveSeconds, ref.original.startedActiveSeconds)
        XCTAssertEqual(set.loggedActiveSeconds, ref.original.loggedActiveSeconds)
        XCTAssertEqual(set.timedActiveSeconds, ref.original.timedActiveSeconds)
        XCTAssertEqual(set.plannedTarget, ref.original.plannedTarget)
        XCTAssertEqual(set.inputTarget, ref.original.inputTarget)
        XCTAssertEqual(set.actual?.loadKG, 52.5)
        XCTAssertEqual(set.actual?.reps, 12)
        XCTAssertEqual(set.actual?.seconds, 10)
        XCTAssertEqual(after.volumeKG, 630)
        XCTAssertEqual(after.completedSets.count, 1)
        XCTAssertEqual(after.telemetry?.events.last?.kind, .setEdited)
        XCTAssertNil(WorkoutHapticPolicy.event(before: before, after: after, now: at(20)))
    }
    @MainActor func testCorrectionWhileNextSetRunsNeverAdvancesOrInterruptsItsClock() throws {
        var value = try session(rest: 0)
        try WorkoutExecutionEngine.apply(.startSet, to: &value, at: at(12))
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(value, at: at(12)))
        let before = try XCTUnwrap(store.active), ref = try XCTUnwrap(before.lastRecordedSet)
        XCTAssertTrue(store.correctRecordedSet(changed(ref), reference: ref, now: at(40)))
        let after = try XCTUnwrap(store.active)
        XCTAssertEqual(after.execution, before.execution)
        XCTAssertEqual(after.executingWork?.set, before.executingWork?.set)
        XCTAssertEqual(after.setElapsed(after.executingWork!.set, at: at(42)), 30)
        XCTAssertEqual(after.remainingSetCount, 1)
    }
    @MainActor func testCompletedCorrectionSurvivesDiskReopenWithoutRestartOrStreakAward() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RecordedSet-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("store")
        let prefs = UserDefaults(suiteName: "RecordedSet-" + UUID().uuidString)!
        defer { prefs.removeObject(forKey: WorkoutStreakStore.storageKey) }
        var expected: WorkoutSession!
        do {
            let store = try WorkoutStore(container: PersistenceFactory.makeContainer(at: url))
            var value = try session(); try WorkoutExecutionEngine.apply(.finish, to: &value, at: at(50))
            XCTAssertTrue(store.save(value, at: at(50)))
            let before = try XCTUnwrap(store.sessions.first), ref = try XCTUnwrap(before.lastRecordedSet)
            let streaks = WorkoutStreakStore(defaults: prefs, sessions: store.sessions, now: at(55))
            XCTAssertTrue(store.correctRecordedSet(changed(ref), reference: ref, now: at(100)))
            expected = store.sessions.first
            XCTAssertNil(store.active)
            XCTAssertEqual(expected.status, .completed)
            XCTAssertEqual(expected.endedAt, before.endedAt)
            XCTAssertEqual(expected.duration(at: at(100)), before.duration(at: at(100)))
            XCTAssertEqual(expected.execution, before.execution)
            streaks.update(sessions: store.sessions, now: at(100))
            XCTAssertNil(streaks.pending)
        }
        let reopened = try WorkoutStore(container: PersistenceFactory.makeContainer(at: url))
        XCTAssertEqual(reopened.sessions.first, expected)
        XCTAssertEqual(reopened.history.first?.volumeKG, 630)
        XCTAssertNil(reopened.active)
    }
    @MainActor func testHistoryCanBeCorrectedWithAnotherWorkoutRunningButCannotBeRestarted() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var past = try session(); try WorkoutExecutionEngine.apply(.finish, to: &past, at: at(50))
        XCTAssertTrue(store.save(past, at: at(50)))
        var current = try session(rest: 0); current.startedAt = at(100)
        XCTAssertTrue(store.save(current, at: at(110)))
        let active = try XCTUnwrap(store.active), ref = try XCTUnwrap(store.history.first?.lastRecordedSet)
        XCTAssertFalse(store.restartRecordedSet(ref, now: at(120)))
        XCTAssertTrue(store.correctRecordedSet(changed(ref), reference: ref, now: at(120)))
        XCTAssertEqual(store.active, active)
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.history.first?.volumeKG, 630)
    }
    func testCorrectionOnlyAcceptsEditablePerformanceAndLeavesStatusClocksAndPlansAlone() throws {
        let ref = try XCTUnwrap(try session().lastRecordedSet)
        var proposal = changed(ref)
        proposal.startedAt = at(100); proposal.completedAt = at(110); proposal.startedActiveSeconds = 100
        proposal.loggedActiveSeconds = 110; proposal.timedActiveSeconds = 99
        proposal.actual?.seconds = 999; proposal.inputTarget?.reps = 99; proposal.restSeconds = 500
        proposal.targetRepMax = 99; proposal.seconds = 999
        var expected = ref.original; expected.loadKG = 52.5; expected.reps = 12; expected.rpe = 8; expected.note = "Corrected result"
        expected.actual?.loadKG = 52.5; expected.actual?.reps = 12
        XCTAssertEqual(try WorkoutRecordedSetEditing.corrected(proposal, original: ref.original, kind: .weighted), expected)
    }
    func testInvalidCorrectionIsRejectedAndCannotTurnPendingSetIntoRecordedSet() throws {
        let ref = try XCTUnwrap(try session().lastRecordedSet)
        for mutation in [
            { (set: inout WorkoutSet) in set.reps = 0 },
            { (set: inout WorkoutSet) in set.loadKG = .nan },
            { (set: inout WorkoutSet) in set.loadKG = 1001 },
            { (set: inout WorkoutSet) in set.rpe = 11 },
            { (set: inout WorkoutSet) in set.note = String(repeating: "x", count: 1001) },
            { (set: inout WorkoutSet) in set.id = UUID() }
        ] {
            var proposed = ref.original; mutation(&proposed)
            XCTAssertThrowsError(try WorkoutRecordedSetEditing.corrected(proposed, original: ref.original, kind: .weighted))
        }
        XCTAssertThrowsError(try WorkoutRecordedSetEditing.corrected(WorkoutSet(), original: WorkoutSet(), kind: .weighted))
    }
    func testDurationCorrectionChangesRecordedPerformanceButPreservesMeasuredClock() throws {
        var original = WorkoutSet(reps: 0, seconds: 30, distanceMeters: 20, completedAt: at(31), startedAt: at(1), startedActiveSeconds: 1,
                                  loggedActiveSeconds: 31, timedActiveSeconds: 30,
                                  actual: WorkoutActual(loadKG: 0, reps: 0, seconds: 30, distanceMeters: 20))
        original.inputTarget = WorkoutActual(loadKG: 0, reps: 0, seconds: 30, distanceMeters: 20)
        var proposed = original; proposed.seconds = 40; proposed.distanceMeters = 50
        let after = try WorkoutRecordedSetEditing.corrected(proposed, original: original, kind: .duration)
        XCTAssertEqual(after.seconds, 40); XCTAssertEqual(after.actual?.seconds, 40)
        XCTAssertEqual(after.distanceMeters, 50); XCTAssertEqual(after.actual?.distanceMeters, 50)
        XCTAssertEqual(after.timedActiveSeconds, 30); XCTAssertEqual(after.startedAt, original.startedAt)
        XCTAssertEqual(after.inputTarget, original.inputTarget)
    }
    func testBodyweightLegacyAndSkippedCorrectionsPreserveTheirMeaning() throws {
        let legacy = WorkoutSet(reps: 8, loadKG: 0, completedAt: at(10))
        var proposed = legacy; proposed.reps = 15; proposed.loadKG = 100
        let after = try WorkoutRecordedSetEditing.corrected(proposed, original: legacy, kind: .bodyweight)
        XCTAssertEqual(after.reps, 15); XCTAssertEqual(after.loadKG, 0); XCTAssertNil(after.actual)
        let skipped = WorkoutSet(reps: 0, skippedAt: at(10))
        var edit = skipped; edit.reps = 12; edit.loadKG = 50
        let corrected = try WorkoutRecordedSetEditing.corrected(edit, original: skipped, kind: .weighted)
        XCTAssertEqual(corrected.status, .skipped); XCTAssertNil(corrected.actual); XCTAssertNil(corrected.completedAt)
        XCTAssertEqual(WorkoutSession(title: "Skipped", entries: [WorkoutEntry(exercise: ExerciseCatalogue.byID["bench"]!, sets: [corrected])]).volumeKG, 0)
    }
    @MainActor func testStaleCorrectionsAndRepeatedRestartsCannotOverwriteLatestRecord() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(try session(), at: at(11)))
        let ref = try XCTUnwrap(store.active?.lastRecordedSet)
        XCTAssertTrue(store.correctRecordedSet(changed(ref), reference: ref, now: at(15)))
        let latest = try XCTUnwrap(store.active)
        XCTAssertFalse(store.correctRecordedSet(ref.original, reference: ref, now: at(16)))
        XCTAssertFalse(store.restartRecordedSet(ref, now: at(16)))
        XCTAssertEqual(store.active, latest)
        let fresh = try XCTUnwrap(latest.lastRecordedSet)
        XCTAssertTrue(store.restartRecordedSet(fresh, now: at(20)))
        let restarted = store.active
        XCTAssertFalse(store.restartRecordedSet(fresh, now: at(21)))
        XCTAssertEqual(store.active, restarted)
    }
    @MainActor func testExplicitRestartClearsResultAndStartsFreshSetWithCorrectedInputs() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(try session(), at: at(11)))
        let ref = try XCTUnwrap(store.active?.lastRecordedSet)
        XCTAssertTrue(store.correctRecordedSet(changed(ref), reference: ref, now: at(15)))
        XCTAssertTrue(store.restartRecordedSet(try XCTUnwrap(store.active?.lastRecordedSet), now: at(20)))
        let after = try XCTUnwrap(store.active), set = try XCTUnwrap(after.executingWork?.set)
        XCTAssertEqual(after.execution?.phase, .activeSet); XCTAssertNil(after.restUntil)
        XCTAssertEqual(set.id, ref.id); XCTAssertEqual(set.status, .pending)
        XCTAssertNil(set.actual); XCTAssertNil(set.completedAt); XCTAssertNil(set.skippedAt)
        XCTAssertEqual(set.reps, 12); XCTAssertEqual(set.loadKG, 52.5)
        XCTAssertEqual(after.setElapsed(set, at: at(25)), 5)
        XCTAssertEqual(after.volumeKG, 0)
    }
    @MainActor func testRestartCompletedSessionExcludesClosedGapFromWorkoutDuration() throws {
        var value = try session(); try WorkoutExecutionEngine.apply(.finish, to: &value, at: at(50))
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(value, at: at(50)))
        XCTAssertTrue(store.restartRecordedSet(try XCTUnwrap(store.history.first?.lastRecordedSet), now: at(200)))
        let after = try XCTUnwrap(store.active)
        XCTAssertEqual(after.status, .inProgress); XCTAssertNil(after.endedAt)
        XCTAssertEqual(after.duration(at: at(210)), 60)
        XCTAssertEqual(after.setElapsed(after.executingWork!.set, at: at(210)), 10)
    }
    @MainActor func testRestartPausedSessionKeepsPauseAndDoesNotStartAnyTimer() throws {
        var value = try session(); value.status = .paused; value.pausedAt = at(15)
        WorkoutExecutionEngine.prepare(&value, at: at(15))
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.save(value, at: at(15)))
        XCTAssertTrue(store.restartRecordedSet(try XCTUnwrap(store.active?.lastRecordedSet), now: at(50)))
        let after = try XCTUnwrap(store.active)
        XCTAssertEqual(after.status, .paused); XCTAssertEqual(after.pausedAt, at(15))
        XCTAssertEqual(after.execution?.phase, .paused); XCTAssertEqual(after.execution?.resumePhase, .ready)
        XCTAssertNil(after.executingWork?.set.startedAt); XCTAssertNil(after.restUntil)
        XCTAssertEqual(after.duration(at: at(60)), 15)
    }
    func testLastRecordedUsesEventTimeInsteadOfExerciseOrderAndIncludesSkippedSets() throws {
        var value = try session()
        let first = try XCTUnwrap(value.lastRecordedSet)
        value.entries[0].sets[1].skippedAt = at(15)
        let skipID = value.entries[0].sets[1].id
        value.entries[0].sets.reverse()
        XCTAssertEqual(value.lastRecordedSet?.id, skipID)
        value.entries[0].sets[0].skippedAt = at(10)
        XCTAssertEqual(value.lastRecordedSet?.id, first.id)
        value.entries[0].sets[0].skippedAt = at(11)
        XCTAssertEqual(value.lastRecordedSet?.id, first.id)
        value.entries[0].sets.removeAll()
        XCTAssertNil(value.lastRecordedSet)
    }
}
