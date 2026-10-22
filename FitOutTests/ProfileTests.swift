import XCTest
#if canImport(FitOutCore)
@testable import FitOutCore
#else
@testable import FitOut
#endif

final class ProfileTests: XCTestCase {
    func testNameValidationAndCompletionRequirements() {
        var profile = FitnessProfile()
        XCTAssertFalse(profile.canComplete)
        profile.name = "  \n "
        XCTAssertFalse(profile.isNameValid)
        profile.name = "Alex"
        XCTAssertTrue(profile.canComplete)
        profile.goals = []
        XCTAssertFalse(profile.canComplete)
        profile.goals = [.strength]
        profile.age = 12
        XCTAssertFalse(profile.canComplete)
        profile.age = 101
        XCTAssertFalse(profile.canComplete)
        profile.age = 35
        profile.currentWeightKG = .nan
        XCTAssertFalse(profile.canComplete)
    }

    func testWeightConversionsDoNotDrift() {
        for kilograms in [25.0, 62, 80.4, 150, 250] {
            let pounds = WeightUnit.lbs.display(kilograms)
            XCTAssertEqual(WeightUnit.lbs.kilograms(pounds), kilograms, accuracy: 0.000001)
            XCTAssertEqual(WeightUnit.kg.display(kilograms), kilograms)
        }
        var profile = FitnessProfile()
        for _ in 0..<100 {
            profile.unit = .lbs
            profile.unit = .kg
        }
        XCTAssertEqual(profile.currentWeightKG, 62)
        XCTAssertEqual(profile.targetWeightKG, 65)
    }

    func testCurrentAndTargetStayIndependent() {
        var profile = FitnessProfile()
        profile.currentWeightKG = 72.6
        XCTAssertEqual(profile.targetWeightKG, 65)
        profile.targetWeightKG = 80
        XCTAssertEqual(profile.currentWeightKG, 72.6)
    }

    func testProfileRoundTripPreservesAvatarAndGoals() throws {
        var profile = FitnessProfile()
        profile.name = "Alex"
        profile.photoData = Data([1, 2, 3, 4])
        profile.usesPhoto = true
        profile.gender = .female
        profile.unit = .lbs
        profile.goals = [.strength, .endurance, .mobility]
        profile.completedAt = Date()
        let data = try JSONEncoder().encode(profile)
        XCTAssertEqual(try JSONDecoder().decode(FitnessProfile.self, from: data), profile)
    }

    @MainActor func testProgressAndCompletionSurviveRelaunch() {
        let suite = "fitout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = OnboardingStore(defaults: defaults)
        first.profile.name = "  Alex  "
        first.profile.age = 32
        first.profile.emoji = "🦁"
        first.step = 3
        let reopened = OnboardingStore(defaults: defaults)
        XCTAssertEqual(reopened.step, 3)
        XCTAssertEqual(reopened.profile.age, 32)
        XCTAssertEqual(reopened.profile.emoji, "🦁")
        XCTAssertTrue(reopened.complete())
        let completed = OnboardingStore(defaults: defaults)
        XCTAssertNotNil(completed.profile.completedAt)
        XCTAssertEqual(completed.profile.name, "Alex")
        completed.editProfile()
        XCTAssertNil(completed.profile.completedAt)
        XCTAssertEqual(completed.step, 1)
        XCTAssertEqual(completed.profile.age, 32)
    }

    @MainActor func testInvalidProfileCannotFinish() {
        let suite = "fitout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.complete())
        XCTAssertNil(store.profile.completedAt)
        store.profile.name = "Alex"
        store.profile.goals = []
        XCTAssertFalse(store.complete())
    }

    @MainActor func testCorruptedStorageRecoversToWelcome() {
        let suite = "fitout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid json".utf8), forKey: "fitout.onboarding.v1")
        let store = OnboardingStore(defaults: defaults)
        XCTAssertEqual(store.step, 0)
        XCTAssertEqual(store.profile, FitnessProfile())
    }

    @MainActor func testRestoredStepIsClamped() throws {
        let suite = "fitout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(OnboardingSnapshot(profile: FitnessProfile(), step: 99)), forKey: "fitout.onboarding.v1")
        XCTAssertEqual(OnboardingStore(defaults: defaults).step, 4)
    }
}
