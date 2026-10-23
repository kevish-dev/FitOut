import XCTest
import SwiftData
@testable import FitOut

final class RoutineFlowTests: XCTestCase {
    func testTemplatesAreEditableAndHaveValidIndependentDays() {
        for template in RoutineTemplate.allCases where template != .custom {
            let routine = template.make()
            XCTAssertNil(routine.readinessMessage, template.rawValue)
            XCTAssertEqual(Set(routine.days.map(\.weekday)), Set(0..<7))
            XCTAssertEqual(Set(routine.days.flatMap(\.exercises).map(\.id)).count, routine.days.flatMap(\.exercises).count)
        }
    }

    func testCopyingADayCreatesIndependentExercisesAndSetTargets() {
        var routine = RoutineTemplate.fullBody.make()
        routine.days[0].exercises[0].setTargets = [PlannedSet(repMin: 10, repMax: 10, loadKG: 20)]
        let source = routine.days[0]
        let destinationID = routine.days[1].id
        RoutineSchedule.copy(source, to: 1, in: &routine)
        XCTAssertEqual(routine.days[1].id, destinationID)
        XCTAssertEqual(routine.days[1].weekday, 1)
        XCTAssertNotEqual(routine.days[1].exercises[0].id, source.exercises[0].id)
        XCTAssertNotEqual(routine.days[1].exercises[0].setTargets?[0].id, source.exercises[0].setTargets?[0].id)
        routine.days[1].exercises[0].setTargets?[0].loadKG = 55
        XCTAssertEqual(routine.days[0].exercises[0].setTargets?[0].loadKG, 20)
        XCTAssertEqual(routine.days[1].exercises[0].setTargets?[0].loadKG, 55)
    }

    func testLegacySetCountsResolveWithoutLosingWarmupsOrRepRanges() throws {
        let plan = PlannedExercise(exerciseID: "bench", sets: 2, repMin: 6, repMax: 8, loadKG: 25, warmupSets: 1)
        let reopened = try JSONDecoder().decode(PlannedExercise.self, from: JSONEncoder().encode(plan))
        XCTAssertNil(reopened.setTargets)
        XCTAssertEqual(reopened.resolvedSets.map(\.type), [.warmup, .working, .working])
        XCTAssertTrue(reopened.resolvedSets.allSatisfy { $0.repMin == 6 && $0.repMax == 8 && $0.loadKG == 25 })
    }

    func testSessionUsesIndividualTargetsWithoutLoggingTargetEffortAsActual() throws {
        var day = RoutineDay(weekday: 0, title: "Chest", kind: .workout, notes: "Use rack safeties")
        day.exercises = [PlannedExercise(exerciseID: "bench", restSeconds: 90, setTargets: [
            PlannedSet(type: .warmup, repMin: 12, repMax: 12, loadKG: 20, restSeconds: 20),
            PlannedSet(repMin: 10, repMax: 10, loadKG: 25, restSeconds: 60, targetRPE: 7),
            PlannedSet(repMin: 8, repMax: 8, loadKG: 30, restSeconds: 90, targetRPE: 8)
        ])]
        let session = try PlannedWorkoutFactory.make(day: day, routineID: UUID(), catalogue: ExerciseCatalogue.all, now: .now)
        XCTAssertEqual(session.notes, "Use rack safeties")
        XCTAssertEqual(session.entries[0].sets.map(\.reps), [12, 10, 8])
        XCTAssertEqual(session.entries[0].sets.map(\.loadKG), [20, 25, 30])
        XCTAssertEqual(session.entries[0].sets.map(\.restSeconds), [20, 60, 90])
        XCTAssertNil(session.entries[0].sets[1].rpe)
        XCTAssertEqual(session.entries[0].sets[1].targetRPE, 7)
        var performed = session
        performed.entries[0].sets[1].loadKG = 35
        performed.entries[0].sets[1].reps = 9
        XCTAssertEqual(performed.entries[0].sets[1].plannedTarget?.loadKG, 25)
        XCTAssertEqual(performed.entries[0].sets[1].plannedTarget?.repMin, 10)
        XCTAssertTrue(session.completedSets.isEmpty)
        XCTAssertEqual(session.volumeKG, 0)
        day.exercises[0].setTargets?[1].loadKG = 99
        XCTAssertEqual(session.entries[0].sets[1].loadKG, 25)
    }

    func testEmptyUnavailableAndInvalidTimedWorkoutsCannotStartPartially() {
        let now = Date()
        XCTAssertThrowsError(try PlannedWorkoutFactory.make(day: RoutineDay(weekday: 0), routineID: nil, catalogue: [], now: now))
        var day = RoutineDay(weekday: 0, title: "Test", kind: .workout, exercises: [PlannedExercise(exerciseID: "missing")])
        XCTAssertThrowsError(try PlannedWorkoutFactory.make(day: day, routineID: nil, catalogue: ExerciseCatalogue.all, now: now))
        day.exercises = [PlannedExercise(exerciseID: "plank", setTargets: [PlannedSet(seconds: 0)])]
        XCTAssertThrowsError(try PlannedWorkoutFactory.make(day: day, routineID: nil, catalogue: ExerciseCatalogue.all, now: now))
        day.exercises[0].setTargets?[0].seconds = 45
        XCTAssertNoThrow(try PlannedWorkoutFactory.make(day: day, routineID: nil, catalogue: ExerciseCatalogue.all, now: now))
        XCTAssertFalse(PlannedSet(loadKG: .nan).isValid)
        XCTAssertFalse(PlannedSet(restSeconds: -1).isValid)
        XCTAssertFalse(PlannedSet(targetRPE: 11).isValid)
    }

    @MainActor func testDraftCommitTrainingAndHistorySurviveRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("routine.store")
        var routine = Routine(name: "My plan", isActive: true)
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        do {
            let database = try PersistenceFactory.makeContainer(at: url)
            let gym = try GymStore(container: database)
            XCTAssertTrue(gym.saveDraft(RoutineDraft(routine: routine, stage: .schedule, weekday: 0)))
            XCTAssertNil(gym.activeRoutine)
        }
        do {
            let database = try PersistenceFactory.makeContainer(at: url)
            let gym = try GymStore(container: database)
            routine = try XCTUnwrap(gym.drafts.first?.routine)
            routine.days[0].kind = .workout; routine.days[0].title = "Push"; routine.days[0].notes = "Notes survive"
            routine.days[0].exercises = [PlannedExercise(exerciseID: "bench", setTargets: [PlannedSet(repMin: 10, repMax: 12, loadKG: 25, restSeconds: 20, targetRPE: 7)])]
            XCTAssertTrue(gym.save(routine, discardDraft: true))
            XCTAssertTrue(gym.drafts.isEmpty)
            XCTAssertNil(gym.readinessError(for: routine))
            let workouts = try WorkoutStore(container: database)
            XCTAssertTrue(workouts.start(day: routine.days[0], routineID: routine.id, catalogue: gym.exercises, now: now))
            let entry = try XCTUnwrap(workouts.active?.entries.first)
            workouts.toggleSet(entryID: entry.id, setID: entry.sets[0].id, now: now)
            XCTAssertEqual(workouts.active?.restUntil, now.addingTimeInterval(20))
            XCTAssertTrue(workouts.finish(.completed, now: now.addingTimeInterval(120)))
        }
        let database = try PersistenceFactory.makeContainer(at: url)
        let gym = try GymStore(container: database)
        let workouts = try WorkoutStore(container: database)
        XCTAssertEqual(gym.activeRoutine?.days[0].notes, "Notes survive")
        XCTAssertEqual(gym.activeRoutine?.days[0].exercises[0].setTargets?[0].loadKG, 25)
        XCTAssertEqual(workouts.history[0].entries[0].sets[0].restSeconds, 20)
        XCTAssertEqual(workouts.history[0].entries[0].sets[0].targetRPE, 7)
        XCTAssertEqual(workouts.history[0].entries[0].sets[0].plannedTarget?.loadKG, 25)
        XCTAssertNil(workouts.history[0].entries[0].sets[0].rpe)
        routine.days[0].exercises[0].setTargets?[0].loadKG = 60
        XCTAssertTrue(gym.save(routine))
        XCTAssertEqual(workouts.history[0].entries[0].sets[0].loadKG, 25)
        XCTAssertTrue(gym.deleteRoutine(routine.id))
        XCTAssertEqual(try WorkoutStore(container: database).history[0].volumeKG, 250)
    }

    @MainActor func testActivationAndArchiveDoNotEraseUnsavedDrafts() throws {
        let gym = try GymStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var routine = RoutineTemplate.fullBody.make()
        XCTAssertTrue(gym.save(routine))
        var edited = routine; edited.name = "Still editing"
        XCTAssertTrue(gym.saveDraft(RoutineDraft(routine: edited)))
        routine.archivedAt = .now
        XCTAssertTrue(gym.save(routine))
        XCTAssertNil(gym.activeRoutine)
        XCTAssertEqual(gym.drafts.first?.routine.name, "Still editing")
        XCTAssertNil(gym.resumableDraft)
        routine.archivedAt = nil; routine.isActive = true
        XCTAssertTrue(gym.save(routine))
        XCTAssertEqual(gym.activeRoutine?.id, routine.id)
        XCTAssertEqual(gym.drafts.count, 1)
    }

    @MainActor func testSavedWorkoutsAreIndependentAndPersisted() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let gym = try GymStore(container: database)
        let day = RoutineTemplate.fullBody.make().days[0]
        XCTAssertTrue(gym.saveWorkout(day))
        let reopened = try GymStore(container: database)
        XCTAssertEqual(reopened.savedWorkouts.count, 1)
        XCTAssertNotEqual(reopened.savedWorkouts[0].day.exercises[0].id, day.exercises[0].id)
        XCTAssertTrue(reopened.deleteSavedWorkout(reopened.savedWorkouts[0].id))
        XCTAssertTrue(reopened.savedWorkouts.isEmpty)
    }

    @MainActor func testV4StoreMigratesWithoutChangingExistingRoutineOrHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("legacy.store")
        let routine = RoutineTemplate.fullBody.make()
        let oldSession = WorkoutSession(title: "Legacy session", status: .completed)
        do {
            let schema = Schema(versionedSchema: FitOutSchemaV4.self)
            let config = ModelConfiguration("FitOut", schema: schema, url: url, cloudKitDatabase: .none)
            let database = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(database)
            context.insert(FitOutSchemaV3.RoutineRecord(routine))
            context.insert(FitOutSchemaV4.SessionRecord(oldSession))
            try context.save()
        }
        let database = try PersistenceFactory.makeContainer(at: url)
        let gym = try GymStore(container: database)
        XCTAssertEqual(gym.routines[0].id, routine.id)
        XCTAssertEqual(gym.routines[0].days[0].exercises[0].sets, 3)
        XCTAssertEqual(try WorkoutStore(container: database).history[0].id, oldSession.id)
        XCTAssertTrue(gym.drafts.isEmpty)
    }
}
