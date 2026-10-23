import XCTest
@testable import FitOut
final class WorkoutTests: XCTestCase {
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
