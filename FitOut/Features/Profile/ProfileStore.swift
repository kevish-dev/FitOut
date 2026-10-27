import Foundation
import SwiftData
import Observation

@MainActor @Observable final class ProfileStore {
    var draft: ProfileData { didSet { if !applying { saveDraft() } } }
    var error: String?
    var onChange: (() -> Void)?
    var onFeedback: ((FitHapticEvent) -> Void)?
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
    @discardableResult func setUnits(weight: WeightUnit? = nil, height: HeightUnit? = nil) -> Bool {
        var value = draft
        if let weight { value.weightUnit = weight }
        if let height { value.heightUnit = height }
        guard value != draft else { error = nil; return true }
        do {
            // Preferences never convert canonical measurements or finish onboarding.
            try persist(value)
            applying = true; draft = value; applying = false
            error = nil; onChange?(); onFeedback?(.selection); return true
        } catch { self.error = error.localizedDescription; onFeedback?(.warning); return false }
    }
    @discardableResult func complete(_ edited: ProfileData? = nil) -> Bool {
        var value = edited ?? draft
        guard value.validationMessage == nil else { error = value.validationMessage; onFeedback?(.warning); return false }
        value.name = value.trimmedName
        value.completedAt = value.completedAt ?? .now
        do {
            try persist(value)
            applying = true; draft = value; applying = false
            error = nil
            onChange?()
            onFeedback?(.saved)
            return true
        } catch { self.error = error.localizedDescription; onFeedback?(.warning); return false }
    }

    #if DEBUG
    func restartForTesting() throws {
        let fresh = ProfileData()
        do {
            try persist(fresh)
            applying = true
            draft = fresh
            applying = false
            error = nil
            onChange?()
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    #endif

    private func persist(_ value: ProfileData) throws {
        do {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV2.UserProfile>()).first { record.update(value) }
            else { context.insert(FitOutSchemaV2.UserProfile(value)) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
