import XCTest
@testable import FitOut
final class WorkoutTests: XCTestCase {
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
