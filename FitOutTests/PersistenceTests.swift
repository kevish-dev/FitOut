import XCTest
import SwiftData
@testable import FitOut

final class PersistenceTests: XCTestCase {
    @MainActor func testNewStoreContainsNoUserData() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(container: container)
        XCTAssertNil(try repository.loadSnapshot())
        XCTAssertEqual(try repository.loadPreferences(), AppPreferences())
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<FitOutSchemaV1.OnboardingRecord>()), 0)
    }

    @MainActor func testSavingUpdatesOneRecordAndKeepsCreatedDate() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let repository = SwiftDataRepository(container: container)
        var snapshot = OnboardingSnapshot()
        snapshot.profile.name = "Alex"
        try repository.saveSnapshot(snapshot)
        let created = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<FitOutSchemaV1.OnboardingRecord>()).first?.createdAt)
        snapshot.profile.currentWeightKG = 72.4
        snapshot.step = 3
        try repository.saveSnapshot(snapshot)
        let records = try ModelContext(container).fetch(FetchDescriptor<FitOutSchemaV1.OnboardingRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.createdAt, created)
        XCTAssertEqual(try repository.loadSnapshot()?.profile.currentWeightKG, 72.4)
        XCTAssertEqual(try repository.loadSnapshot()?.step, 3)
    }

    @MainActor func testDiskStoreSurvivesContainerRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        var expected = OnboardingSnapshot()
        expected.profile.name = "Alex"
        expected.profile.photoData = Data([1, 2, 3])
        expected.profile.usesPhoto = true
        expected.profile.unit = .lbs
        expected.profile.goals = [.muscle, .health]
        expected.step = 4
        do {
            let repository = SwiftDataRepository(container: try PersistenceFactory.makeContainer(at: url))
            try repository.saveSnapshot(expected)
            try repository.savePreferences(AppPreferences(appearance: .system, hapticsEnabled: false))
        }
        let reopened = SwiftDataRepository(container: try PersistenceFactory.makeContainer(at: url))
        XCTAssertEqual(try reopened.loadSnapshot()?.profile, expected.profile)
        XCTAssertEqual(try reopened.loadSnapshot()?.step, 4)
        XCTAssertEqual(try reopened.loadPreferences(), AppPreferences(appearance: .system, hapticsEnabled: false))
    }

    @MainActor func testLegacyImportIsLosslessIdempotentAndKeepsBackup() throws {
        let suite = "fitout.import.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var snapshot = OnboardingSnapshot()
        snapshot.profile.name = "Existing user"
        snapshot.profile.emoji = "🦁"
        snapshot.profile.photoData = Data([7, 8, 9])
        snapshot.step = 2
        let original = try JSONEncoder().encode(snapshot)
        defaults.set(original, forKey: LegacyOnboardingImporter.key)
        let repository = SwiftDataRepository(container: try PersistenceFactory.makeContainer(inMemory: true))
        try LegacyOnboardingImporter.importIfNeeded(from: defaults, into: repository)
        XCTAssertEqual(try repository.loadSnapshot()?.profile, snapshot.profile)
        XCTAssertEqual(defaults.data(forKey: LegacyOnboardingImporter.key), original)
        snapshot.profile.name = "Updated in SwiftData"
        try repository.saveSnapshot(snapshot)
        try LegacyOnboardingImporter.importIfNeeded(from: defaults, into: repository)
        XCTAssertEqual(try repository.loadSnapshot()?.profile.name, "Updated in SwiftData")
    }

    @MainActor func testBadLegacyDataIsPreservedAndNotSilentlyReplaced() throws {
        let suite = "fitout.import.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("unreadable".utf8)
        defaults.set(original, forKey: LegacyOnboardingImporter.key)
        let repository = SwiftDataRepository(container: try PersistenceFactory.makeContainer(inMemory: true))
        XCTAssertThrowsError(try LegacyOnboardingImporter.importIfNeeded(from: defaults, into: repository))
        XCTAssertNil(try repository.loadSnapshot())
        XCTAssertEqual(defaults.data(forKey: LegacyOnboardingImporter.key), original)
    }

    func testInvalidStoreLocationFailsWithoutMemoryFallback() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("preserve me".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        XCTAssertThrowsError(try PersistenceFactory.makeContainer(at: blocker.appendingPathComponent("store")))
        XCTAssertEqual(try Data(contentsOf: blocker), Data("preserve me".utf8))
    }
}
