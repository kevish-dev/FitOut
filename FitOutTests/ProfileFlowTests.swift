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
    @MainActor func testLegacyGoalsRequireExplicitPrimarySelection() throws {
        var old = FitnessProfile(); old.name = "Alex"; old.completedAt = .now
        let store = try ProfileStore(container: PersistenceFactory.makeContainer(inMemory: true), legacy: OnboardingSnapshot(profile: old, step: 4))
        XCTAssertEqual(store.draft.name, "Alex"); XCTAssertNil(store.draft.primaryGoal)
        XCTAssertNil(store.draft.completedAt); XCTAssertFalse(store.complete())
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
