import Foundation
import Observation

@MainActor @Observable
final class OnboardingStore {
    var profile: FitnessProfile { didSet { if !applying { persist() } } }
    var step: Int { didSet { if !applying { persist() } } }
    var storageError: String?
    private let repository: any OnboardingRepository
    private var applying = false

    init(repository: any OnboardingRepository) throws {
        self.repository = repository
        let saved = try repository.loadSnapshot()
        profile = saved?.profile ?? FitnessProfile()
        step = min(max(saved?.step ?? 0, 0), 4)
        if profile.completedAt != nil && !profile.canComplete {
            profile.completedAt = nil
            step = 1
        }
    }

    @discardableResult func complete() -> Bool {
        guard profile.canComplete else { return false }
        var candidate = profile
        candidate.name = candidate.trimmedName
        candidate.completedAt = Date()
        do {
            try repository.saveSnapshot(OnboardingSnapshot(profile: candidate, step: step))
            applying = true
            profile = candidate
            applying = false
            storageError = nil
            return true
        } catch { storageError = error.localizedDescription; return false }
    }

    func editProfile() { profile.completedAt = nil; step = 1 }
    func persist() {
        do {
            try repository.saveSnapshot(OnboardingSnapshot(profile: profile, step: step))
            storageError = nil
        } catch { storageError = error.localizedDescription }
    }
}
