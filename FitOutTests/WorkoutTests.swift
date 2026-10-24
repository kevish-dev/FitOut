import XCTest
@testable import FitOut
final class WorkoutTests: XCTestCase {
    @MainActor func testPrecisePausesLapsAndEvidenceSurviveReload() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try WorkoutStore(container: database)
        let start = Date(timeIntervalSince1970: 30_000)
        XCTAssertTrue(store.start(catalogue: [], now: start))
        store.pause(now: start.addingTimeInterval(10.25))
        store.resume(now: start.addingTimeInterval(20.75))
        store.markLap(now: start.addingTimeInterval(30.5))
        store.markLap(now: start.addingTimeInterval(45.75))
        let reopened = try WorkoutStore(container: database)
        let session = try XCTUnwrap(reopened.active)
        XCTAssertEqual(session.pausedSeconds, 10.5, accuracy: 0.001)
        let log = try XCTUnwrap(session.telemetry)
        XCTAssertEqual(log.pauses.count, 1)
        XCTAssertEqual(log.pauses[0].endedAt, start.addingTimeInterval(20.75))
        XCTAssertEqual(log.laps.count, 2)
        XCTAssertEqual(log.laps[0].activeSeconds, 20, accuracy: 0.001)
        XCTAssertEqual(log.laps[0].wallSeconds, 30.5, accuracy: 0.001)
        XCTAssertEqual(log.laps[1].activeSeconds, 15.25, accuracy: 0.001)
        XCTAssertEqual(log.laps[1].elapsedActiveSeconds, 35.25, accuracy: 0.001)
        reopened.pause(now: start.addingTimeInterval(50))
        XCTAssertTrue(reopened.finish(.abandoned, now: start.addingTimeInterval(70)))
        let ended = try XCTUnwrap(reopened.history.first)
        XCTAssertEqual(ended.duration(), 39.5, accuracy: 0.001)
        XCTAssertEqual(ended.totalPaused(), 30.5, accuracy: 0.001)
        XCTAssertEqual(ended.telemetry?.pauses.last?.endedAt, ended.endedAt)
    }

    @MainActor func testSetClockExcludesPausesAndStopsBeforeLoggingOrUndo() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let start = Date(timeIntervalSince1970: 40_000)
        let entry = WorkoutEntry(exercise: try XCTUnwrap(ExerciseCatalogue.all.first { $0.kind == .duration }), sets: [WorkoutSet(seconds: 30)])
        let setID = entry.sets[0].id
        XCTAssertTrue(store.start(catalogue: [], now: start))
        store.update(at: start) { $0.entries = [entry] }
        store.startSet(entryID: entry.id, setID: setID, now: start.addingTimeInterval(5))
        store.pause(now: start.addingTimeInterval(15))
        store.resume(now: start.addingTimeInterval(25))
        store.stopSetTimer(entryID: entry.id, setID: setID, now: start.addingTimeInterval(35))
        let stopped = try XCTUnwrap(store.active?.entries[0].sets[0])
        XCTAssertEqual(stopped.seconds, 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(store.active?.setElapsed(stopped, at: start.addingTimeInterval(100))), 20, accuracy: 0.001)
        store.toggleSet(entryID: entry.id, setID: setID, now: start.addingTimeInterval(45))
        let logged = try XCTUnwrap(store.active?.entries[0].sets[0])
        XCTAssertEqual(logged.seconds, 20, accuracy: 0.001)
        XCTAssertEqual(logged.loggedActiveSeconds, 35)
        XCTAssertEqual(logged.timedActiveSeconds, 20)
        store.toggleSet(entryID: entry.id, setID: setID, now: start.addingTimeInterval(46))
        let undone = try XCTUnwrap(store.active?.entries[0].sets[0])
        XCTAssertNil(undone.startedAt); XCTAssertNil(undone.startedActiveSeconds); XCTAssertNil(undone.timedActiveSeconds)
        XCTAssertEqual(undone.seconds, 20)
        let undo = try XCTUnwrap(store.active?.telemetry?.events.last { $0.kind == .setUndone })
        XCTAssertEqual(undo.beforeSet?.completedAt, start.addingTimeInterval(45))
        XCTAssertEqual(undo.beforeSet?.timedActiveSeconds, 20)
        let next = logged.nextWorkingSet()
        XCTAssertNil(next.startedAt); XCTAssertNil(next.startedActiveSeconds); XCTAssertNil(next.loggedActiveSeconds); XCTAssertNil(next.timedActiveSeconds)
    }

    @MainActor func testRunningDurationUsesMeasuredTimeAndKeepsDeletedSetEvidence() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let start = Date(timeIntervalSince1970: 50_000)
        let entry = WorkoutEntry(exercise: try XCTUnwrap(ExerciseCatalogue.all.first { $0.kind == .duration }), sets: [WorkoutSet(seconds: 0)])
        XCTAssertTrue(store.start(catalogue: [], now: start))
        store.update(at: start) { $0.entries = [entry] }
        store.startSet(entryID: entry.id, setID: entry.sets[0].id, now: start.addingTimeInterval(5))
        store.toggleSet(entryID: entry.id, setID: entry.sets[0].id, now: start.addingTimeInterval(22.25))
        XCTAssertEqual(store.active?.completedSets.first?.seconds, 17.25)
        store.update(at: start.addingTimeInterval(23)) { $0.entries[0].sets[0].rpe = 8 }
        store.update(at: start.addingTimeInterval(24)) { $0.entries[0].sets[0].rpe = 9 }
        XCTAssertEqual(store.active?.telemetry?.events.filter { $0.kind == .setEdited }.count, 1)
        store.update(at: start.addingTimeInterval(25)) { $0.entries[0].sets.removeAll() }
        let deleted = try XCTUnwrap(store.active?.telemetry?.events.last { $0.kind == .setDeleted })
        XCTAssertEqual(deleted.beforeSet?.seconds, 17.25)
        XCTAssertEqual(deleted.beforeSet?.rpe, 9)
        XCTAssertEqual(deleted.exerciseName, entry.exercise.name)
    }

    @MainActor func testLiveActionsAreIdempotentAndCannotMutateAnotherSession() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try WorkoutStore(container: database)
        let start = Date(timeIntervalSince1970: 60_000)
        XCTAssertTrue(store.start(catalogue: [], now: start))
        let sessionID = try XCTUnwrap(store.active?.id), commandID = UUID()
        XCTAssertTrue(store.runQuickAction("lap", sessionID: sessionID, commandID: commandID, now: start.addingTimeInterval(10)))
        let reopened = try WorkoutStore(container: database)
        XCTAssertTrue(reopened.runQuickAction("lap", sessionID: sessionID, commandID: commandID, now: start.addingTimeInterval(11)))
        XCTAssertEqual(reopened.active?.telemetry?.laps.count, 1)
        XCTAssertEqual(reopened.active?.telemetry?.events.last?.origin, .liveActivity)
        XCTAssertFalse(reopened.runQuickAction("pause", sessionID: UUID(), commandID: UUID()))
        XCTAssertEqual(reopened.active?.status, .inProgress)
        XCTAssertTrue(reopened.finish(.abandoned, now: start.addingTimeInterval(15)))
        XCTAssertTrue(reopened.start(catalogue: [], now: start.addingTimeInterval(16)))
        XCTAssertFalse(reopened.runQuickAction("pause", sessionID: sessionID, commandID: UUID()))
        XCTAssertEqual(reopened.active?.status, .inProgress)
    }

    @MainActor func testSwitchingSetTimersPreservesMeasurementWithoutLogging() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let start = Date(timeIntervalSince1970: 65_000)
        let entry = WorkoutEntry(exercise: try XCTUnwrap(ExerciseCatalogue.all.first { $0.kind == .duration }), sets: [WorkoutSet(), WorkoutSet()])
        XCTAssertTrue(store.start(catalogue: [], now: start))
        store.update(at: start) { $0.entries = [entry] }
        store.startSet(entryID: entry.id, setID: entry.sets[0].id, now: start.addingTimeInterval(5))
        store.startSet(entryID: entry.id, setID: entry.sets[1].id, now: start.addingTimeInterval(20))
        let session = try XCTUnwrap(store.active)
        XCTAssertEqual(session.entries[0].sets[0].timedActiveSeconds, 15)
        XCTAssertEqual(session.entries[0].sets[0].seconds, 15)
        XCTAssertNil(session.entries[0].sets[0].completedAt)
        XCTAssertNil(session.entries[0].sets[1].timedActiveSeconds)
        XCTAssertEqual(session.focusedWork?.set.id, entry.sets[1].id)
        XCTAssertEqual(session.telemetry?.events.filter { $0.kind == .setTimerStopped }.count, 1)
        XCTAssertTrue(store.finish(.abandoned, now: start.addingTimeInterval(30)))
        XCTAssertEqual(store.history[0].entries[0].sets[1].timedActiveSeconds, 10)
        XCTAssertTrue(store.history[0].completedSets.isEmpty)
    }

    func testExpiredRestUsesItsDeadlineInsteadOfReopeningTime() throws {
        let start = Date(timeIntervalSince1970: 68_000)
        var before = WorkoutSession(title: "Rest", startedAt: start, restUntil: start.addingTimeInterval(30))
        before.telemetry = WorkoutTelemetry(recordedSince: start, baselinePausedSeconds: 0)
        var after = before; after.restUntil = start.addingTimeInterval(100)
        let result = WorkoutTelemetryRecorder.prepare(after, before: before, at: start.addingTimeInterval(60), origin: .app)
        let events = try XCTUnwrap(result.telemetry).events.filter { $0.kind == .restChanged }
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].date, start.addingTimeInterval(30))
        XCTAssertEqual(events[0].activeSeconds, 30)
        XCTAssertEqual(events[1].date, start.addingTimeInterval(60))
        XCTAssertEqual(events[1].afterDeadline, start.addingTimeInterval(100))
    }

    func testOldSupplementAndSessionDecodeWithoutTimingKeys() throws {
        let oldSupplement = try JSONDecoder().decode(SessionPlanDetails.self, from: Data("{\"sets\":[]}".utf8))
        XCTAssertNil(oldSupplement.telemetry)
        var set = WorkoutSet(startedAt: .now, startedActiveSeconds: 2, loggedActiveSeconds: 12, timedActiveSeconds: 10)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as? [String: Any])
        for key in ["startedAt", "startedActiveSeconds", "loggedActiveSeconds", "timedActiveSeconds"] { object.removeValue(forKey: key) }
        set = try JSONDecoder().decode(WorkoutSet.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(set.startedAt); XCTAssertNil(set.timedActiveSeconds)
        let old = WorkoutSession(title: "Older session")
        let decoded = try JSONDecoder().decode(WorkoutSession.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.telemetry)
        var restored = decoded
        restored.telemetry = WorkoutTelemetry(recordedSince: .now, baselinePausedSeconds: 0)
        restored = oldSupplement.applying(to: restored)
        XCTAssertNil(restored.telemetry)
    }

    func testLegacyTrackingDoesNotInventEarlierEvents() {
        let start = Date(timeIntervalSince1970: 70_000)
        let old = WorkoutSession(title: "Previously running", startedAt: start, pausedSeconds: 20,
            entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(completedAt: start.addingTimeInterval(10))])])
        let new = WorkoutTelemetryRecorder.prepare(old, before: old, at: start.addingTimeInterval(100), origin: .app)
        XCTAssertEqual(new.telemetry?.events.map(\.kind), [.trackingEnabled])
        XCTAssertEqual(new.telemetry?.recordedSince, start.addingTimeInterval(100))
        XCTAssertEqual(new.telemetry?.baselinePausedSeconds, 20)
        XCTAssertEqual(new.completedSets.count, 1)
    }

    @MainActor func testLiveActivityProjectionHasCorrectClocksAndBoundedPayload() throws {
        let start = Date(timeIntervalSince1970: 80_000)
        var session = WorkoutSession(title: String(repeating: "🏋️", count: 500), startedAt: start, pausedSeconds: 10)
        let set = WorkoutSet(startedAt: start.addingTimeInterval(20), startedActiveSeconds: 15)
        var entry = WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [set])
        entry.exercise.name = String(repeating: "Lift", count: 1000)
        session.entries = [entry]
        let state = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: start.addingTimeInterval(40))
        XCTAssertEqual(state.clockStart, start.addingTimeInterval(10))
        XCTAssertEqual(state.elapsed, 30)
        XCTAssertEqual(state.setTimerElapsed, 15)
        XCTAssertEqual(state.setTimerStart, start.addingTimeInterval(25))
        XCTAssertLessThan(try JSONEncoder().encode(state).count, 4096)
        session.status = .paused; session.pausedAt = start.addingTimeInterval(40)
        let paused = WorkoutPresentationCoordinator.content(for: session, unit: .kg, now: start.addingTimeInterval(100))
        XCTAssertEqual(paused.elapsed, 30); XCTAssertNil(paused.setTimerStart); XCTAssertEqual(paused.setTimerElapsed, 15)
    }

    @MainActor func testBatchAddingPreservesSelectionOrderAndSavesOnce() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.start(catalogue: ExerciseCatalogue.all))
        var writes = 0
        store.onChange = { writes += 1 }
        let chosen = ["pulldown", "bench", "crunch"].compactMap { ExerciseCatalogue.byID[$0] }
        XCTAssertTrue(store.add(chosen))
        XCTAssertEqual(store.active?.entries.map { $0.exercise.id }, chosen.map(\.id))
        XCTAssertEqual(store.active?.entries.map { $0.sets.count }, [1, 1, 1])
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(try XCTUnwrap(store.active).completedSets.isEmpty)
        XCTAssertFalse(store.add([]))
        XCTAssertEqual(writes, 1)
    }

    @MainActor func testPauseFreezesRestAcrossStoreReloadAndDoesNotReviveExpiredRest() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try WorkoutStore(container: database)
        let start = Date(timeIntervalSince1970: 20_000)
        XCTAssertTrue(store.start(catalogue: ExerciseCatalogue.all, now: start))
        store.add(ExerciseCatalogue.all[0])
        let entry = try XCTUnwrap(store.active?.entries.first)
        store.toggleSet(entryID: entry.id, setID: entry.sets[0].id, now: start.addingTimeInterval(10))
        XCTAssertEqual(store.active?.restUntil, start.addingTimeInterval(100))
        XCTAssertEqual(store.active?.currentRestDuration, 90)
        store.pause(now: start.addingTimeInterval(30))
        XCTAssertEqual(store.active?.restRemaining(at: start.addingTimeInterval(300)), 70)
        let reopened = try WorkoutStore(container: database)
        reopened.resume(now: start.addingTimeInterval(130))
        XCTAssertEqual(reopened.active?.restUntil, start.addingTimeInterval(200))
        XCTAssertEqual(reopened.active?.restRemaining(at: start.addingTimeInterval(130)), 70)
        XCTAssertEqual(reopened.active?.duration(at: start.addingTimeInterval(130)), 30)
        reopened.pause(now: start.addingTimeInterval(210))
        reopened.resume(now: start.addingTimeInterval(260))
        XCTAssertNil(reopened.active?.restUntil)
    }

    func testNextSetCopiesInputsWithoutCreatingLoggedEvidenceOrPlanTargets() {
        let set = WorkoutSet(type: .warmup, reps: 12, loadKG: 25, seconds: 45, distanceMeters: 200,
            rpe: 8, completedAt: .now, restSeconds: 40, targetRPE: 9, targetRepMax: 15, plannedTarget: PlannedSet())
        let next = set.nextWorkingSet()
        XCTAssertNotEqual(next.id, set.id)
        XCTAssertEqual(next.type, .working)
        XCTAssertEqual(next.reps, 12); XCTAssertEqual(next.loadKG, 25)
        XCTAssertEqual(next.seconds, 45); XCTAssertEqual(next.distanceMeters, 200)
        XCTAssertNil(next.completedAt); XCTAssertNil(next.rpe); XCTAssertNil(next.restSeconds)
        XCTAssertNil(next.targetRPE); XCTAssertNil(next.targetRepMax); XCTAssertNil(next.plannedTarget)
    }

    func testSetProgressKeepsLoggedSetsAndExcludesSkippedUnloggedTargets() {
        let logged = WorkoutSet(completedAt: .now)
        var session = WorkoutSession(title: "Test")
        session.entries = [
            WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [logged, WorkoutSet(), WorkoutSet()]),
            WorkoutEntry(exercise: ExerciseCatalogue.all[1], sets: [logged, WorkoutSet()], skipped: true)
        ]
        XCTAssertEqual(session.completedSets.count, 2)
        XCTAssertEqual(session.remainingSetCount, 2)
        XCTAssertEqual(session.trackedSetCount, 4)
        XCTAssertEqual(session.setProgress, 0.5)
        session.entries[0].skipped = true
        XCTAssertEqual(session.setProgress, 1)
        XCTAssertEqual(WorkoutSession(title: "Empty").setProgress, 0)
    }

    @MainActor func testInterruptedWorkoutReopensFromDiskAndHistoryIsIndependent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("workouts.store")
        let start = Date(timeIntervalSince1970: 10000)
        do {
            let db = try PersistenceFactory.makeContainer(at: url)
            let gym = try GymStore(container: db); let workouts = try WorkoutStore(container: db)
            let routine = RoutineTemplate.fullBody.make(); XCTAssertTrue(gym.save(routine))
            XCTAssertTrue(workouts.start(day: routine.days[0], routineID: routine.id, catalogue: gym.exercises, now: start))
            workouts.update { $0.entries[0].sets[0].reps = 10; $0.entries[0].sets[0].loadKG = 50 }
            let e = workouts.active!.entries[0]
            workouts.toggleSet(entryID: e.id, setID: e.sets[0].id, now: start.addingTimeInterval(60))
            workouts.pause(now: start.addingTimeInterval(90))
        }
        let db = try PersistenceFactory.makeContainer(at: url)
        let workouts = try WorkoutStore(container: db)
        XCTAssertEqual(workouts.active?.completedSets.count, 1)
        XCTAssertEqual(workouts.active?.volumeKG, 500)
        XCTAssertEqual(workouts.active?.status, .paused)
        workouts.resume(now: start.addingTimeInterval(120))
        XCTAssertTrue(workouts.finish(.completed, now: start.addingTimeInterval(180)))
        XCTAssertEqual(workouts.history[0].duration(), 150)
        let gym = try GymStore(container: db); XCTAssertTrue(gym.deleteRoutine(gym.routines[0].id))
        XCTAssertEqual(workouts.history[0].entries[0].exercise.name, "Squat")
        XCTAssertEqual(try WorkoutStore(container: db).history[0].volumeKG, 500)
    }
    @MainActor func testInvalidSetAndDuplicateStartAreRejected() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.start(catalogue: [])); XCTAssertFalse(store.start(catalogue: []))
        store.add(ExerciseCatalogue.all[0]); XCTAssertFalse(store.update { $0.entries[0].sets[0].loadKG = .nan })
        XCTAssertEqual(store.active?.entries[0].sets[0].loadKG, 0)
        XCTAssertFalse(store.finish(.completed)); XCTAssertTrue(store.finish(.skipped))
        XCTAssertEqual(store.history[0].status, .skipped)
    }
    func testVolumeExcludesWarmupsBodyweightDurationAndIncompleteSets() {
        let working = WorkoutSet(reps: 10, loadKG: 40, completedAt: .now)
        let warmup = WorkoutSet(type: .warmup, reps: 10, loadKG: 20, completedAt: .now)
        var session = WorkoutSession(title: "Test")
        session.entries = [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [working, warmup, WorkoutSet(loadKG: 100)]), WorkoutEntry(exercise: ExerciseCatalogue.all.first { $0.kind == .bodyweight }!, sets: [working])]
        XCTAssertEqual(session.volumeKG, 400)
    }
}
