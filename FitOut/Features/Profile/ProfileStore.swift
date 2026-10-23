import Foundation
import SwiftData
import Observation

@MainActor @Observable final class ProfileStore {
    var draft: ProfileData { didSet { if !applying { saveDraft() } } }
    var error: String?
    private var applying = false
    private let context: ModelContext
    init(container: ModelContainer, legacy: OnboardingSnapshot?) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        if let saved = try context.fetch(FetchDescriptor<FitOutSchemaV2.UserProfile>()).first {
            draft = saved.value
        } else {
            var value = ProfileData()
            if let old = legacy?.profile {
                value.name = old.name; value.age = old.age; value.gender = old.gender
                value.currentWeightKG = old.currentWeightKG; value.targetWeightKG = old.targetWeightKG
                value.weightUnit = old.unit; value.emoji = old.emoji
                value.avatarData = old.usesPhoto ? old.photoData : nil
                // A legacy multi-goal selection is never silently converted to a primary goal.
                value.step = 1
            }
            draft = value
        }
    }
    func saveDraft() { do { try persist(draft); error = nil } catch { self.error = error.localizedDescription } }
    @discardableResult func complete(_ edited: ProfileData? = nil) -> Bool {
        var value = edited ?? draft
        guard value.validationMessage == nil else { error = value.validationMessage; return false }
        value.name = value.trimmedName
        value.completedAt = value.completedAt ?? .now
        do {
            try persist(value)
            applying = true; draft = value; applying = false
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func persist(_ value: ProfileData) throws {
        do {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV2.UserProfile>()).first { record.update(value) }
            else { context.insert(FitOutSchemaV2.UserProfile(value)) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
