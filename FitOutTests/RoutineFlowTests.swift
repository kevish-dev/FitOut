import XCTest
import SwiftData
import SwiftUI
@testable import FitOut

final class RoutineFlowTests: XCTestCase {
    @MainActor func testRapidStageAndDayAutosavesDoNotPublishCommittedPlanChangesOrRewriteIdenticalDrafts() throws {
        let gym = try GymStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let routine = RoutineTemplate.fullBody.make()
        XCTAssertTrue(gym.save(routine))
        let committed = gym.routines, catalogue = gym.exercises
        var published = 0; gym.onChange = { published += 1 }
        for stage in RoutineEditorStage.allCases {
            for weekday in 0..<7 {
                var draft = RoutineDraft(routine: routine, stage: stage, weekday: weekday)
                XCTAssertTrue(gym.saveDraft(draft))
                let stored = try XCTUnwrap(gym.drafts.first)
                draft.updatedAt = .distantFuture
                XCTAssertTrue(gym.saveDraft(draft))
                XCTAssertEqual(gym.drafts.first, stored)
                XCTAssertEqual(gym.drafts.count, 1)
                XCTAssertEqual(gym.drafts.first?.stage, stage)
                XCTAssertEqual(gym.drafts.first?.weekday, weekday)
            }
        }
        XCTAssertEqual(published, 0)
        XCTAssertEqual(gym.routines, committed)
        XCTAssertEqual(gym.exercises, catalogue)
        XCTAssertTrue(gym.savedWorkouts.isEmpty)
    }
    @MainActor func testDraftOnlyAutosaveSurvivesDiskReopenWithoutChangingSavedRoutine() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DraftStability-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("gym.store")
        var saved: Routine!, draft: RoutineDraft!
        do {
            let gym = try GymStore(container: PersistenceFactory.makeContainer(at: url))
            XCTAssertTrue(gym.save(RoutineTemplate.fullBody.make())); saved = gym.activeRoutine
            var editing = try XCTUnwrap(saved); editing.days.reverse()
            editing.days[0].title = "Unsaved title"
            XCTAssertTrue(gym.saveDraft(RoutineDraft(routine: editing, stage: .workouts, weekday: 6)))
            draft = gym.drafts.first
        }
        let reopened = try GymStore(container: PersistenceFactory.makeContainer(at: url))
        XCTAssertEqual(reopened.activeRoutine, saved)
        XCTAssertEqual(reopened.drafts.first, draft)
    }
    @MainActor func testFocusedDayBindingStillEditsItsOriginalDayAfterOrderAndWeekdayChange() {
        let fixture = RoutineBindingFixture()
        let original = fixture.routine.days[0], other = fixture.routine.days[1]
        let binding = fixture.binding.days.identifiedElement(id: original.id, fallback: original)
        RoutineSchedule.move(dayID: original.id, to: 2, in: &fixture.routine)
        fixture.routine.days.reverse()
        binding.title.wrappedValue = "Original day, edited"
        XCTAssertEqual(fixture.routine.days.first { $0.id == original.id }?.title, "Original day, edited")
        XCTAssertEqual(fixture.routine.days.first { $0.id == original.id }?.weekday, 2)
        XCTAssertEqual(fixture.routine.days.first { $0.id == other.id }, other)
    }
    @MainActor func testRemovedExerciseBindingCannotWriteIntoAnotherExerciseAtTheSameOffset() {
        let fixture = RoutineBindingFixture()
        let day = fixture.routine.days[0], plan = day.exercises[0]
        let binding = fixture.binding.days.identifiedElement(id: day.id, fallback: day)
            .exercises.identifiedElement(id: plan.id, fallback: plan)
        fixture.routine.days[0].exercises.removeFirst()
        let before = fixture.routine
        binding.notes.wrappedValue = "Late keyboard commit"
        XCTAssertEqual(fixture.routine, before)
        XCTAssertEqual(binding.wrappedValue, plan)
    }
    @MainActor func testSetBindingSurvivesReorderAndIgnoresLateInputAfterDeletion() {
        let fixture = RoutineBindingFixture()
        fixture.routine.days[0].exercises[0].setTargets = [PlannedSet(loadKG: 20), PlannedSet(loadKG: 30)]
        let day = fixture.routine.days[0], plan = day.exercises[0], target = plan.setTargets![0]
        let planBinding = fixture.binding.days.identifiedElement(id: day.id, fallback: day)
            .exercises.identifiedElement(id: plan.id, fallback: plan)
        let targets = Binding(get: { planBinding.wrappedValue.setTargets ?? [] }, set: { planBinding.wrappedValue.setTargets = $0 })
        let binding = targets.identifiedElement(id: target.id, fallback: target)
        fixture.routine.days[0].exercises[0].setTargets?.reverse()
        binding.loadKG.wrappedValue = 45
        XCTAssertEqual(fixture.routine.days[0].exercises[0].setTargets?.last?.loadKG, 45)
        XCTAssertEqual(fixture.routine.days[0].exercises[0].setTargets?.first?.loadKG, 30)
        fixture.routine.days[0].exercises[0].setTargets?.removeAll { $0.id == target.id }
        let before = fixture.routine
        binding.repMin.wrappedValue = 99
        XCTAssertEqual(fixture.routine, before)
        var changedID = target; changedID.id = UUID()
        binding.wrappedValue = changedID
        XCTAssertEqual(fixture.routine, before)
    }
    @MainActor func testNestedBindingCannotResurrectADeletedParentDay() {
        let fixture = RoutineBindingFixture()
        let day = fixture.routine.days[0], plan = day.exercises[0]
        let binding = fixture.binding.days.identifiedElement(id: day.id, fallback: day)
            .exercises.identifiedElement(id: plan.id, fallback: plan)
        fixture.routine.days.removeAll { $0.id == day.id }
        let before = fixture.routine
        binding.restSeconds.wrappedValue = 300
        XCTAssertEqual(fixture.routine, before)
        XCTAssertEqual(binding.wrappedValue, plan)
    }
    @MainActor func testEveryRestAndOpenDayCanBeEditedWithoutDependingOnItsArrayOffset() {
        let fixture = RoutineBindingFixture()
        fixture.routine.days.reverse()
        for weekday in 0..<7 {
            let day = fixture.routine.days.first { $0.weekday == weekday }!
            let binding = fixture.binding.days.identifiedElement(id: day.id, fallback: day)
            let otherDays = fixture.routine.days.filter { $0.id != day.id }
            binding.kind.wrappedValue = weekday.isMultiple(of: 2) ? .rest : .flexible
            binding.notes.wrappedValue = "Day \(weekday)"
            XCTAssertEqual(fixture.routine.days.filter { $0.id != day.id }, otherDays)
            XCTAssertEqual(fixture.routine.days.first { $0.weekday == weekday }?.notes, "Day \(weekday)")
        }
    }
    func testPickerRouteRetainsOriginalDayAfterMoveAndRejectsRemovedDay() {
        var routine = RoutineTemplate.fullBody.make()
        let original = routine.days[0]
        let route = RoutineBuilderSheet(dayID: original.id, action: .add)
        let other = RoutineBuilderSheet(dayID: routine.days[1].id, action: .add)
        XCTAssertNotEqual(route.id, other.id)
        RoutineSchedule.move(dayID: original.id, to: 4, in: &routine)
        routine.days.reverse()
        XCTAssertEqual(route.targetDay(in: routine)?.id, original.id)
        XCTAssertEqual(route.targetDay(in: routine)?.weekday, 4)
        routine.days.removeAll { $0.id == original.id }
        XCTAssertNil(route.targetDay(in: routine))
        XCTAssertNotNil(other.targetDay(in: routine))
    }
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

@MainActor private final class RoutineBindingFixture {
    var routine = RoutineTemplate.fullBody.make()
    var binding: Binding<Routine> { Binding(get: { self.routine }, set: { self.routine = $0 }) }
}
