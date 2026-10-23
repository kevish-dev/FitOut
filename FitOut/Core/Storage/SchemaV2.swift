import Foundation
import SwiftData

enum FitOutSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { FitOutSchemaV1.models + [UserProfile.self] }
    @Model final class UserProfile {
        @Attribute(.unique) var key: String
        var name: String
        var age: Int
        var genderRaw: String?
        var heightCM: Double
        var currentWeightKG: Double
        var targetWeightKG: Double?
        var weightUnitRaw: String
        var heightUnitRaw: String
        var primaryGoalRaw: String?
        var emoji: String
        @Attribute(.externalStorage) var avatarData: Data?
        var completedAt: Date?
        var step: Int
        var createdAt: Date
        var updatedAt: Date
        init(_ value: ProfileData) {
            key = "profile"; name = value.name; age = value.age; genderRaw = value.gender?.rawValue
            heightCM = value.heightCM; currentWeightKG = value.currentWeightKG; targetWeightKG = value.targetWeightKG
            weightUnitRaw = value.weightUnit.rawValue; heightUnitRaw = value.heightUnit.rawValue
            primaryGoalRaw = value.primaryGoal?.rawValue; emoji = value.emoji; avatarData = value.avatarData
            completedAt = value.completedAt; step = value.step; createdAt = .now; updatedAt = .now
        }
        func update(_ value: ProfileData) {
            name = value.name; age = value.age; genderRaw = value.gender?.rawValue
            heightCM = value.heightCM; currentWeightKG = value.currentWeightKG; targetWeightKG = value.targetWeightKG
            weightUnitRaw = value.weightUnit.rawValue; heightUnitRaw = value.heightUnit.rawValue
            primaryGoalRaw = value.primaryGoal?.rawValue; emoji = value.emoji; avatarData = value.avatarData
            completedAt = value.completedAt; step = value.step; updatedAt = .now
        }
        var value: ProfileData {
            ProfileData(name: name, age: age, gender: genderRaw.flatMap(Gender.init(rawValue:)), heightCM: heightCM,
                        currentWeightKG: currentWeightKG, targetWeightKG: targetWeightKG,
                        weightUnit: WeightUnit(rawValue: weightUnitRaw) ?? .kg, heightUnit: HeightUnit(rawValue: heightUnitRaw) ?? .cm,
                        primaryGoal: primaryGoalRaw.flatMap(PrimaryGoal.init(rawValue:)), emoji: emoji,
                        avatarData: avatarData, completedAt: completedAt, step: step)
        }
    }
}
