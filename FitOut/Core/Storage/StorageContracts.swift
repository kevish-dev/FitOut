import Foundation

@MainActor
protocol OnboardingRepository {
    func loadSnapshot() throws -> OnboardingSnapshot?
    func saveSnapshot(_ snapshot: OnboardingSnapshot) throws
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
}

struct AppPreferences: Equatable {
    var appearance: AppAppearance = .dark
    var hapticsEnabled = true
}

@MainActor
protocol PreferencesRepository {
    func loadPreferences() throws -> AppPreferences
    func savePreferences(_ preferences: AppPreferences) throws
}

enum StorageError: LocalizedError {
    case unreadableLegacyProfile
    var errorDescription: String? {
        "The existing profile could not be read. Its saved data has been preserved."
    }
}

// The old format is retained only as an import source; never write new production data here.
enum LegacyOnboardingImporter {
    static let key = "fitout.onboarding.v1"

    @MainActor static func importIfNeeded(from defaults: UserDefaults, into repository: any OnboardingRepository) throws {
        guard try repository.loadSnapshot() == nil,
              let data = defaults.data(forKey: key) else { return }
        guard var snapshot = try? JSONDecoder().decode(OnboardingSnapshot.self, from: data) else {
            throw StorageError.unreadableLegacyProfile
        }
        snapshot.step = min(4, max(0, snapshot.step))
        try repository.saveSnapshot(snapshot)
        // Keep the original until a later, explicit data-management operation. A present
        // SwiftData record makes import idempotent, including after an interrupted launch.
    }
}
