import Foundation
import Observation

@MainActor @Observable
final class OnboardingStore {
    var profile: FitnessProfile { didSet { persist() } }
    var step: Int { didSet { persist() } }
    var storageError: String?
    private let defaults: UserDefaults
    private static let key = "fitout.onboarding.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(OnboardingSnapshot.self, from: $0) }
        profile = saved?.profile ?? FitnessProfile()
        step = min(max(saved?.step ?? 0, 0), 4)
        if profile.completedAt != nil && !profile.canComplete {
            profile.completedAt = nil
            step = 1
        }
    }

    @discardableResult func complete() -> Bool {
        guard profile.canComplete else { return false }
        profile.name = profile.trimmedName
        profile.completedAt = Date()
        return true
    }

    func editProfile() {
        profile.completedAt = nil
        step = 1
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(OnboardingSnapshot(profile: profile, step: step)), forKey: Self.key)
        } catch {
            storageError = "Your changes could not be saved. Please try again."
        }
    }
}
