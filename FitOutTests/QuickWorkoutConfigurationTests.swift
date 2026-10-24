import XCTest
@testable import FitOut

final class QuickWorkoutConfigurationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 300_000)
    private var exercise: ExerciseDefinition { ExerciseCatalogue.all[0] }
    private func draft() -> QuickWorkoutDraft {
        var value = QuickWorkoutDraft()
        value.add([exercise, ExerciseCatalogue.all[1]], current: nil, history: [])
        return value
    }
    @MainActor func testConfiguringAndRestoringDraftNeverCreatesSessionOrTimer() throws {
        let defaults = UserDefaults(suiteName: "quick-setup-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: QuickWorkoutDraftStore.key) }
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let setup = QuickWorkoutDraftStore(defaults: defaults)
        setup.draft.add([exercise], current: nil, history: [])
        setup.draft.entries[0].sets[0].loadKG = 42.5
        setup.draft.entries[0].sets[0].reps = 12
        XCTAssertNil(store.active); XCTAssertTrue(store.sessions.isEmpty)
        let restored = QuickWorkoutDraftStore(defaults: defaults)
        XCTAssertEqual(restored.draft, setup.draft)
        XCTAssertEqual(restored.draft.entries[0].sets.count, 3)
        XCTAssertTrue(restored.draft.entries[0].sets.allSatisfy { $0.startedAt == nil && $0.actual == nil })
        restored.clear()
        XCTAssertTrue(QuickWorkoutDraftStore(defaults: defaults).draft.entries.isEmpty)
    }
    @MainActor func testExplicitStartBeginsOnlyConfiguredFirstSetAndKeepsInputs() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true), store = try WorkoutStore(container: database)
        var setup = draft()
        setup.title = "  Upper body  "
        setup.entries[0].sets[0].loadKG = 57.5; setup.entries[0].sets[0].reps = 9
        XCTAssertTrue(store.startQuickWorkout(setup, unit: .lbs, now: date))
        let session = try XCTUnwrap(store.active)
        XCTAssertEqual(session.title, "Upper body"); XCTAssertEqual(session.startedAt, date)
        XCTAssertEqual(session.execution?.phase, .activeSet); XCTAssertEqual(session.execution?.preferredUnit, .lbs)
        XCTAssertEqual(session.entries.map(\.exercise.id), setup.entries.map(\.exercise.id))
        XCTAssertEqual(session.entries[0].sets[0].startedAt, date)
        XCTAssertEqual(session.entries[0].sets[0].loadKG, 57.5); XCTAssertEqual(session.entries[0].sets[0].reps, 9)
        XCTAssertTrue(session.entries.flatMap(\.sets).dropFirst().allSatisfy { $0.startedAt == nil })
        XCTAssertTrue(session.completedSets.isEmpty); XCTAssertEqual(session.volumeKG, 0)
        XCTAssertEqual(try WorkoutStore(container: database).active, session)
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg, now: date.addingTimeInterval(100)))
        XCTAssertEqual(store.sessions.count, 1)
    }
    @MainActor func testStartRejectsEmptyInvalidDuplicateAndAlreadyLoggedTargets() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var setup = draft()
        XCTAssertFalse(store.startQuickWorkout(QuickWorkoutDraft(), unit: .kg))
        setup.entries[0].sets[0].reps = 0
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg))
        setup.entries[0].sets[0].reps = 8; setup.entries[0].sets[0].loadKG = .nan
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg))
        setup = draft(); setup.entries[0].sets.append(setup.entries[0].sets[0])
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg))
        setup = draft(); setup.entries[0].sets[0].completedAt = date
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg))
        setup = draft(); setup.entries[0].sets[0].startedAt = date
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg))
        XCTAssertTrue(store.sessions.isEmpty)
    }
    func testSetupRecallsPerSetInputsAndCountFromRecordedExercise() {
        let old = WorkoutEntry(exercise: exercise, sets: [
            WorkoutSet(type: .warmup, reps: 15, loadKG: 10, completedAt: date),
            WorkoutSet(reps: 10, loadKG: 50, completedAt: date.addingTimeInterval(10)),
            WorkoutSet(reps: 8, loadKG: 55, completedAt: date.addingTimeInterval(20))], restSeconds: 75)
        let history = WorkoutSession(title: "Previous", startedAt: date, endedAt: date.addingTimeInterval(30), status: .completed, entries: [old])
        var setup = QuickWorkoutDraft(); setup.add([exercise, exercise], current: nil, history: [history])
        XCTAssertEqual(setup.entries.count, 1); XCTAssertEqual(setup.entries[0].sets.count, 2)
        XCTAssertEqual(setup.entries[0].sets.map(\.loadKG), [50, 55])
        XCTAssertEqual(setup.entries[0].sets.map(\.reps), [10, 8])
        XCTAssertEqual(setup.entries[0].restSeconds, 75)
        XCTAssertTrue(setup.entries[0].sets.allSatisfy { $0.completedAt == nil && $0.actual == nil && $0.startedAt == nil })
    }
    @MainActor func testConfiguredLaterTargetsAreNotFlattenedByEarlierCompletion() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var setup = draft()
        setup.entries[0].sets[0].loadKG = 40; setup.entries[0].sets[1].loadKG = 55; setup.entries[0].sets[2].loadKG = 65
        XCTAssertTrue(store.startQuickWorkout(setup, unit: .kg, now: date))
        let session = try XCTUnwrap(store.active)
        store.update(at: date.addingTimeInterval(1)) { $0.entries[0].sets[0].loadKG = 45 }
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: session.id, now: date.addingTimeInterval(10)))
        XCTAssertEqual(store.active?.entries[0].sets.map(\.loadKG), [45, 55, 65])
    }
    @MainActor func testAddingConfiguredExercisesDoesNotStartOrChangeCurrentSetTimer() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.startQuickWorkout(draft(), unit: .kg, now: date))
        let before = try XCTUnwrap(store.active)
        var additions = QuickWorkoutDraft(); additions.add([ExerciseCatalogue.all[2]], current: before, history: [])
        additions.entries[0].sets[0].loadKG = 27.5
        XCTAssertTrue(store.addConfiguredExercises(additions.entries, now: date.addingTimeInterval(1)))
        XCTAssertEqual(store.active?.execution?.setID, before.execution?.setID)
        XCTAssertEqual(store.active?.entries[0], before.entries[0])
        XCTAssertEqual(store.active?.entries.last?.sets.first?.loadKG, 27.5)
        XCTAssertTrue(store.active?.entries.last?.sets.allSatisfy { $0.startedAt == nil && $0.completedAt == nil } == true)
        XCTAssertFalse(store.addConfiguredExercises([]))
    }
    @MainActor func testEditingRunningExercisePreservesTimersAndCanExtendAndRemoveFutureSets() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.startQuickWorkout(draft(), unit: .kg, now: date))
        let original = try XCTUnwrap(store.active?.entries.first)
        var edited = original
        edited.sets[0].loadKG = 60; edited.sets[0].reps = 12
        edited.sets.removeLast(); edited.sets.append(WorkoutSet(reps: 6, loadKG: 70))
        XCTAssertTrue(store.configureExercise(edited, original: original, now: date.addingTimeInterval(15)))
        let result = try XCTUnwrap(store.active?.entries.first)
        XCTAssertEqual(result.sets.count, 3); XCTAssertEqual(result.sets[0].loadKG, 60)
        XCTAssertEqual(result.sets[0].startedAt, original.sets[0].startedAt)
        XCTAssertEqual(result.sets[0].startedActiveSeconds, original.sets[0].startedActiveSeconds)
        XCTAssertEqual(result.sets[0].inputTarget, original.sets[0].inputTarget)
        XCTAssertNil(result.sets.last?.startedAt); XCTAssertEqual(result.sets.last?.loadKG, 70)
    }
    @MainActor func testEditingCannotDeleteCurrentSetOrLoseConcurrentAddedSets() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.startQuickWorkout(draft(), unit: .kg, now: date))
        let original = try XCTUnwrap(store.active?.entries.first)
        var edited = original; edited.sets.removeFirst()
        XCTAssertFalse(store.configureExercise(edited, original: original, now: date.addingTimeInterval(15)))
        XCTAssertEqual(store.active?.entries.first, original)
        edited = original; edited.sets[1].reps = 15
        XCTAssertTrue(store.appendSet(entryID: original.id))
        XCTAssertFalse(store.configureExercise(edited, original: original, now: date.addingTimeInterval(15)))
        XCTAssertEqual(store.active?.entries.first?.sets.count, 4)
    }
    @MainActor func testCompletedRecordsCannotBeRewrittenAndRestDefaultDoesNotChangeLoggedRest() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.startQuickWorkout(draft(), unit: .kg, now: date))
        let id = try XCTUnwrap(store.active?.id)
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: id, now: date.addingTimeInterval(10)))
        let original = try XCTUnwrap(store.active?.entries.first), deadline = store.active?.restUntil
        var edited = original
        edited.sets[0].loadKG = 999; edited.sets[0].reps = 999; edited.sets[1].loadKG = 62.5
        edited.restSeconds = 15
        XCTAssertTrue(store.configureExercise(edited, original: original, now: date.addingTimeInterval(15)))
        let result = try XCTUnwrap(store.active?.entries.first)
        XCTAssertEqual(result.sets[0].loadKG, original.sets[0].loadKG)
        XCTAssertEqual(result.sets[0].actual, original.sets[0].actual)
        XCTAssertEqual(result.sets[0].restSeconds, original.restSeconds)
        XCTAssertEqual(result.sets[1].loadKG, 62.5); XCTAssertEqual(result.sets[1].restSeconds, 15)
        XCTAssertEqual(store.active?.restUntil, deadline)
    }
    @MainActor func testStalePendingEditDoesNotOverwriteSetCompletedWhileEditorOpen() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertTrue(store.startQuickWorkout(draft(), unit: .kg, now: date))
        let original = try XCTUnwrap(store.active?.entries.first), id = try XCTUnwrap(store.active?.id)
        var edited = original; edited.sets[0].loadKG = 100
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: id, now: date.addingTimeInterval(10)))
        XCTAssertFalse(store.configureExercise(edited, original: original, now: date.addingTimeInterval(15)))
        XCTAssertEqual(store.active?.entries.first?.sets[0].actual?.loadKG, original.sets[0].loadKG)
    }
    func testTypedInputValidationSupportsUnitsDecimalsAndRejectsInvalidText() {
        XCTAssertEqual(WorkoutConfigurationValue.parse("52,5", maximum: 1000, integer: false, positive: false, decimalSeparator: ","), 52.5)
        XCTAssertEqual(WorkoutConfigurationValue.parse("0", maximum: 1000, integer: false, positive: false), 0)
        for text in ["", "-1", "NaN", "inf", "1001", "5.5"] {
            XCTAssertNil(WorkoutConfigurationValue.parse(text, maximum: 1000, integer: true, positive: true), text)
        }
        XCTAssertNil(WorkoutConfigurationValue.parse("0", maximum: 86400, integer: false, positive: true))
        XCTAssertEqual(WorkoutConfigurationValue.parse("2200.5", maximum: WeightUnit.lbs.display(1000), integer: false, positive: false, decimalSeparator: "."), 2200.5)
    }

    @MainActor func testSetupOrderRemainsTheSessionOrderAndEmptyRestIsRejected() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var setup = draft(); setup.entries.swapAt(0, 1)
        setup.entries[0].restSeconds = -1
        XCTAssertFalse(store.startQuickWorkout(setup, unit: .kg, now: date))
        setup.entries[0].restSeconds = 0
        XCTAssertTrue(store.startQuickWorkout(setup, unit: .kg, now: date))
        XCTAssertEqual(store.active?.entries.first?.exercise.id, setup.entries.first?.exercise.id)
        XCTAssertEqual(store.active?.execution?.entryID, store.active?.entries.first?.id)
    }

    @MainActor func testReplayingRetainedSetupCreatesFreshIDsWithoutChangingHistory() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true)), setup = draft()
        XCTAssertTrue(store.startQuickWorkout(setup, unit: .kg, now: date))
        let first = try XCTUnwrap(store.active)
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: first.id, now: date.addingTimeInterval(10)))
        XCTAssertTrue(store.performFocused(.finish, sessionID: first.id, now: date.addingTimeInterval(11)))
        let saved = try XCTUnwrap(store.history.first)
        XCTAssertTrue(store.startQuickWorkout(setup, unit: .kg, now: date.addingTimeInterval(100)))
        let next = try XCTUnwrap(store.active)
        XCTAssertTrue(Set(next.entries.map(\.id)).isDisjoint(with: Set(first.entries.map(\.id))))
        XCTAssertTrue(Set(next.entries.flatMap(\.sets).map(\.id)).isDisjoint(with: Set(first.entries.flatMap(\.sets).map(\.id))))
        XCTAssertEqual(store.history.first, saved)
    }

    func testTimedAndBodyweightConfigurationValidateAppropriateInputs() {
        var timed = exercise; timed.kind = .duration
        var setup = QuickWorkoutDraft(); setup.add([timed], current: nil, history: [])
        XCTAssertTrue(setup.isValid); XCTAssertEqual(setup.entries[0].sets[0].seconds, 30)
        setup.entries[0].sets[0].seconds = 0; XCTAssertFalse(setup.isValid)
        var bodyweight = exercise; bodyweight.kind = .bodyweight
        setup = QuickWorkoutDraft(); setup.add([bodyweight], current: nil, history: [])
        XCTAssertTrue(setup.isValid)
        setup.entries[0].sets[0].reps = 0; XCTAssertFalse(setup.isValid)
    }
}
