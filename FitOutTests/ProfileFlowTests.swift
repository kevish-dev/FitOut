import XCTest
import SwiftData
@testable import FitOut

final class ProfileFlowTests: XCTestCase {
    func testOptionalFieldsAndSingleGoalValidation() {
        var p = ProfileData()
        p.name = "Alex"
        XCTAssertNotNil(p.validationMessage)
        p.primaryGoal = .fitness
        XCTAssertNil(p.gender); XCTAssertNil(p.targetWeightKG)
        XCTAssertNil(p.validationMessage)
        p.primaryGoal = .strength
        XCTAssertEqual(p.primaryGoal, .strength)
        p.heightCM = .infinity; XCTAssertNotNil(p.validationMessage)
        p.heightCM = 170; p.targetWeightKG = -1; XCTAssertNotNil(p.validationMessage)
    }
    func testHeightUnitRoundTrip() {
        for cm in [80.0, 165.1, 182.88, 250] {
            let parts = ProfileData.feetAndInches(cm)
            XCTAssertEqual(ProfileData.centimeters(feet: parts.feet, inches: parts.inches), cm, accuracy: 0.000001)
        }
    }
    @MainActor func testProfilePersistsAndEditsWithoutRestartingOnboarding() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try ProfileStore(container: container, legacy: nil)
        store.draft.name = "  Alex  "; store.draft.primaryGoal = .recomposition; store.draft.step = 2
        XCTAssertTrue(store.complete())
        let reopened = try ProfileStore(container: container, legacy: nil)
        XCTAssertEqual(reopened.draft.name, "Alex")
        XCTAssertNotNil(reopened.draft.completedAt)
        var edit = reopened.draft; edit.heightCM = 180; edit.primaryGoal = .strength
        XCTAssertTrue(reopened.complete(edit))
        XCTAssertEqual(try ProfileStore(container: container, legacy: nil).draft.heightCM, 180)
        XCTAssertNotNil(reopened.draft.completedAt)
    }

    #if DEBUG
    @MainActor func testTestingRestartReturnsToFirstOnboardingStepAndKeepsWorkouts() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let profile = try ProfileStore(container: container, legacy: nil)
        profile.draft.name = "Alex"
        profile.draft.primaryGoal = .fitness
        XCTAssertTrue(profile.complete())
        let workouts = try WorkoutStore(container: container)
        XCTAssertTrue(workouts.start(catalogue: []))

        try profile.restartForTesting()

        XCTAssertEqual(profile.draft, ProfileData())
        XCTAssertEqual(try ProfileStore(container: container, legacy: nil).draft, ProfileData())
        XCTAssertNotNil(try WorkoutStore(container: container).active)
    }
    #endif

    @MainActor func testLegacyGoalsRequireExplicitPrimarySelection() throws {
        var old = FitnessProfile(); old.name = "Alex"; old.completedAt = .now
        let store = try ProfileStore(container: PersistenceFactory.makeContainer(inMemory: true), legacy: OnboardingSnapshot(profile: old, step: 4))
        XCTAssertEqual(store.draft.name, "Alex"); XCTAssertNil(store.draft.primaryGoal)
        XCTAssertNil(store.draft.completedAt); XCTAssertFalse(store.complete())
    }
    @MainActor func testUnitSettingsPersistWithoutConvertingMeasurementsOrCompletingOnboarding() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UnitPreferences-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.store")
        var expected: ProfileData!
        do {
            let profile = try ProfileStore(container: PersistenceFactory.makeContainer(at: url), legacy: nil)
            let original = profile.draft
            var changes = 0; profile.onChange = { changes += 1 }
            XCTAssertTrue(profile.setUnits(weight: .lbs, height: .feet))
            XCTAssertNil(profile.draft.completedAt); XCTAssertEqual(profile.draft.step, original.step)
            XCTAssertEqual(profile.draft.currentWeightKG, original.currentWeightKG)
            XCTAssertEqual(profile.draft.targetWeightKG, original.targetWeightKG)
            XCTAssertEqual(profile.draft.heightCM, original.heightCM)
            XCTAssertEqual(profile.draft.name, original.name)
            XCTAssertTrue(profile.setUnits(weight: .lbs, height: .feet))
            XCTAssertEqual(changes, 1)
            expected = profile.draft
        }
        let reopened = try ProfileStore(container: PersistenceFactory.makeContainer(at: url), legacy: nil)
        XCTAssertEqual(reopened.draft, expected)
    }
    @MainActor func testSettingsUnitChangeUpdatesWorkoutAndWidgetProjectionWithoutRewritingSessionsOrRoutine() throws {
        let suite = "UnitIntegration-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            if let id = defaults.string(forKey: "hydration.test.storageID") {
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("FitOutHydrationTests/" + id))
            }
            defaults.removePersistentDomain(forName: suite)
        }
        let app = try AppContainer(database: PersistenceFactory.makeContainer(inMemory: true), capabilities: UnitCapabilityStub(), defaults: defaults)
        app.profile.draft.name = "Alex"; app.profile.draft.primaryGoal = .strength
        XCTAssertTrue(app.profile.complete())
        XCTAssertTrue(app.gym.save(RoutineTemplate.fullBody.make()))
        let routine = app.gym.activeRoutine
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.byID["bench"]!, sets: [WorkoutSet(reps: 8, loadKG: 50)])])
        XCTAssertTrue(app.workouts.startQuickWorkout(draft, unit: .kg))
        let before = app.workouts.sessions, model = FocusedWorkoutModel(store: app.workouts, unit: .kg)
        XCTAssertEqual(model.unit, .kg)
        XCTAssertTrue(app.profile.setUnits(weight: .lbs))
        XCTAssertEqual(model.unit, .lbs)
        XCTAssertTrue(app.hydration.state.snapshot.usesPounds)
        XCTAssertEqual(app.workouts.sessions, before)
        XCTAssertEqual(app.gym.activeRoutine, routine)
        XCTAssertTrue(app.profile.setUnits(weight: .kg))
        XCTAssertEqual(model.unit, .kg)
        XCTAssertFalse(app.hydration.state.snapshot.usesPounds)
        XCTAssertEqual(app.workouts.sessions, before)
    }
    @MainActor func testOldUnitPickerCallbackCannotReinterpretWeightAfterSettingsChange() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.byID["bench"]!, sets: [WorkoutSet(reps: 8, loadKG: 50)])])
        XCTAssertTrue(store.startQuickWorkout(draft, unit: .kg))
        let model = FocusedWorkoutModel(store: store, unit: .kg)
        let before = try XCTUnwrap(store.active), id = try XCTUnwrap(model.current?.set.id)
        store.setDisplayWeightUnit(.lbs)
        XCTAssertEqual(model.unit, .lbs)
        model.editDisplayedLoad(100, unit: .kg, setID: id)
        XCTAssertEqual(store.active, before)
        model.editDisplayedLoad(WeightUnit.lbs.display(55), unit: .lbs, setID: id)
        XCTAssertEqual(try XCTUnwrap(model.current?.set.loadKG), 55, accuracy: 0.000001)
        XCTAssertEqual(model.current?.set.startedAt, before.executingWork?.set.startedAt)
        XCTAssertEqual(store.active?.execution?.phase, .activeSet)
    }
    @MainActor func testWaterDisplayPreferenceSurvivesRelaunchAndNeverChangesLoggedAmountsOrGoals() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("WaterUnits-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shared = WidgetSharedStore(directory: folder), store = HydrationStore(shared: shared)
        XCTAssertEqual(store.waterDisplayUnit, "ml")
        store.log(250); XCTAssertTrue(store.saveGoals(WidgetGoals(waterML: 2_500)))
        let water = store.state.water, goals = store.state.goals
        store.displayUnit("L")
        let reopened = HydrationStore(shared: WidgetSharedStore(directory: folder))
        XCTAssertEqual(reopened.waterDisplayUnit, "L")
        XCTAssertEqual(reopened.state.water, water); XCTAssertEqual(reopened.state.goals, goals)
        reopened.displayUnit("invalid")
        XCTAssertEqual(reopened.waterDisplayUnit, "L")
        XCTAssertEqual(reopened.state.water, water)
    }
    @MainActor func testV1DatabaseMigratesWithoutLosingLegacyDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.store")
        do {
            let schema = Schema(versionedSchema: FitOutSchemaV1.self)
            let configuration = ModelConfiguration("FitOut", schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: configuration)
            let repository = SwiftDataRepository(container: old)
            var profile = FitnessProfile(); profile.name = "Migration"
            try repository.saveSnapshot(OnboardingSnapshot(profile: profile, step: 2))
        }
        let migrated = try PersistenceFactory.makeContainer(at: url)
        XCTAssertEqual(try SwiftDataRepository(container: migrated).loadSnapshot()?.profile.name, "Migration")
        let profile = try ProfileStore(container: migrated, legacy: SwiftDataRepository(container: migrated).loadSnapshot())
        XCTAssertEqual(profile.draft.name, "Migration")
        profile.draft.primaryGoal = .muscle
        XCTAssertTrue(profile.complete())
    }

}

@MainActor private struct UnitCapabilityStub: RuntimeCapabilityProviding {
    func currentCapabilities() -> CapabilitySnapshot {
        .init(healthKit: .unavailable(.systemUnavailable), foundationModels: .unavailable(.systemUnavailable), imagePlayground: .unavailable(.systemUnavailable))
    }
}
