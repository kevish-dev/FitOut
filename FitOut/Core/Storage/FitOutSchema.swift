import Foundation
import SwiftData

// V1 preserves the existing reference-onboarding draft without inventing a primary goal.
// Phase 1 introduces the PRD UserProfile through a new schema/migration.
enum FitOutSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [OnboardingRecord.self, PreferencesRecord.self] }

    @Model final class OnboardingRecord {
        @Attribute(.unique) var key: String
        var name: String
        var age: Int
        var genderRaw: String
        var currentWeightKG: Double
        var targetWeightKG: Double
        var weightUnitRaw: String
        var legacyGoalIDs: [String]
        var avatarEmoji: String
        var usesPhoto: Bool
        @Attribute(.externalStorage) var avatarData: Data?
        var step: Int
        var completedAt: Date?
        var createdAt: Date
        var updatedAt: Date

        init(snapshot: OnboardingSnapshot, now: Date = .now) {
            key = "local-profile"
            name = snapshot.profile.name
            age = snapshot.profile.age
            genderRaw = snapshot.profile.gender.rawValue
            currentWeightKG = snapshot.profile.currentWeightKG
            targetWeightKG = snapshot.profile.targetWeightKG
            weightUnitRaw = snapshot.profile.unit.rawValue
            legacyGoalIDs = snapshot.profile.goals.map(\.rawValue).sorted()
            avatarEmoji = snapshot.profile.emoji
            usesPhoto = snapshot.profile.usesPhoto
            avatarData = snapshot.profile.photoData
            step = snapshot.step
            completedAt = snapshot.profile.completedAt
            createdAt = now
            updatedAt = now
        }

        func update(from snapshot: OnboardingSnapshot, now: Date = .now) {
            name = snapshot.profile.name
            age = snapshot.profile.age
            genderRaw = snapshot.profile.gender.rawValue
            currentWeightKG = snapshot.profile.currentWeightKG
            targetWeightKG = snapshot.profile.targetWeightKG
            weightUnitRaw = snapshot.profile.unit.rawValue
            legacyGoalIDs = snapshot.profile.goals.map(\.rawValue).sorted()
            avatarEmoji = snapshot.profile.emoji
            usesPhoto = snapshot.profile.usesPhoto
            avatarData = snapshot.profile.photoData
            step = snapshot.step
            completedAt = snapshot.profile.completedAt
            updatedAt = now
        }

        var snapshot: OnboardingSnapshot {
            var profile = FitnessProfile()
            profile.name = name
            profile.age = age
            profile.gender = Gender(rawValue: genderRaw) ?? .male
            profile.currentWeightKG = currentWeightKG
            profile.targetWeightKG = targetWeightKG
            profile.unit = WeightUnit(rawValue: weightUnitRaw) ?? .kg
            profile.goals = Set(legacyGoalIDs.compactMap(FitnessGoal.init(rawValue:)))
            profile.emoji = avatarEmoji
            profile.usesPhoto = usesPhoto
            profile.photoData = avatarData
            profile.completedAt = completedAt
            return OnboardingSnapshot(profile: profile, step: min(4, max(0, step)))
        }
    }

    @Model final class PreferencesRecord {
        @Attribute(.unique) var key: String
        var appearanceRaw: String
        var hapticsEnabled: Bool
        init(preferences: AppPreferences) {
            key = "local-preferences"
            appearanceRaw = preferences.appearance.rawValue
            hapticsEnabled = preferences.hapticsEnabled
        }
    }
}

enum FitOutMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FitOutSchemaV1.self, FitOutSchemaV2.self, FitOutSchemaV3.self, FitOutSchemaV4.self, FitOutSchemaV5.self, FitOutSchemaV6.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: FitOutSchemaV1.self, toVersion: FitOutSchemaV2.self), .lightweight(fromVersion: FitOutSchemaV2.self, toVersion: FitOutSchemaV3.self), .lightweight(fromVersion: FitOutSchemaV3.self, toVersion: FitOutSchemaV4.self), .lightweight(fromVersion: FitOutSchemaV4.self, toVersion: FitOutSchemaV5.self), .lightweight(fromVersion: FitOutSchemaV5.self, toVersion: FitOutSchemaV6.self)] }
}
