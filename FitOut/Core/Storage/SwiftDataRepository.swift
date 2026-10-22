import Foundation
import SwiftData

@MainActor final class SwiftDataRepository: OnboardingRepository, PreferencesRepository {
    private let context: ModelContext
    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func loadSnapshot() throws -> OnboardingSnapshot? {
        try context.fetch(FetchDescriptor<FitOutSchemaV1.OnboardingRecord>()).first?.snapshot
    }

    func saveSnapshot(_ snapshot: OnboardingSnapshot) throws {
        do {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV1.OnboardingRecord>()).first {
                record.update(from: snapshot)
            } else {
                context.insert(FitOutSchemaV1.OnboardingRecord(snapshot: snapshot))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func loadPreferences() throws -> AppPreferences {
        guard let record = try context.fetch(FetchDescriptor<FitOutSchemaV1.PreferencesRecord>()).first else { return AppPreferences() }
        return AppPreferences(appearance: AppAppearance(rawValue: record.appearanceRaw) ?? .dark, hapticsEnabled: record.hapticsEnabled)
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        do {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV1.PreferencesRecord>()).first {
                record.appearanceRaw = preferences.appearance.rawValue
                record.hapticsEnabled = preferences.hapticsEnabled
            } else {
                context.insert(FitOutSchemaV1.PreferencesRecord(preferences: preferences))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
