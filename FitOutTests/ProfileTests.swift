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

    @MainActor func testProgressAndCompletionSurviveRelaunch() throws {
        let repository = TestOnboardingRepository()
        let first = try OnboardingStore(repository: repository)
        first.profile.name = "  Alex  "
        first.profile.age = 32
        first.step = 3
        let reopened = try OnboardingStore(repository: repository)
        XCTAssertEqual(reopened.step, 3)
        XCTAssertEqual(reopened.profile.age, 32)
        XCTAssertTrue(reopened.complete())
        let completed = try OnboardingStore(repository: repository)
        XCTAssertNotNil(completed.profile.completedAt)
        XCTAssertEqual(completed.profile.name, "Alex")
    }

    @MainActor func testInvalidProfileCannotFinish() throws {
        let store = try OnboardingStore(repository: TestOnboardingRepository())
        XCTAssertFalse(store.complete())
        XCTAssertNil(store.profile.completedAt)
    }

    @MainActor func testFailedCompletionDoesNotNavigate() throws {
        let repository = TestOnboardingRepository()
        let store = try OnboardingStore(repository: repository)
        store.profile.name = "Alex"
        repository.shouldFail = true
        XCTAssertFalse(store.complete())
        XCTAssertNil(store.profile.completedAt)
        XCTAssertNotNil(store.storageError)
        repository.shouldFail = false
        XCTAssertTrue(store.complete())
        XCTAssertNil(store.storageError)
    }

    @MainActor func testRestoredStepIsClamped() throws {
        let repository = TestOnboardingRepository()
        repository.snapshot = OnboardingSnapshot(profile: FitnessProfile(), step: 99)
        XCTAssertEqual(try OnboardingStore(repository: repository).step, 4)
    }
}

@MainActor final class TestOnboardingRepository: OnboardingRepository {
    var snapshot: OnboardingSnapshot?
    var shouldFail = false
    func loadSnapshot() throws -> OnboardingSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: OnboardingSnapshot) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        self.snapshot = snapshot
    }
}
