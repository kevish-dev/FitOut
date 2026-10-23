import Foundation
import SwiftData

// Nutrition is additive. Existing profile, gym and session schemas remain frozen.
enum FitOutSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        FitOutSchemaV5.models + [FoodRecord.self, FoodEntryRecord.self, RecipeRecord.self, SavedMealRecord.self, TargetRecord.self, NutritionSettingsRecord.self]
    }
    @Model final class FoodRecord {
        @Attribute(.unique) var id: String
        var payload: Data
        init(id: String, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class FoodEntryRecord {
        @Attribute(.unique) var id: UUID
        var date: Date
        var payload: Data
        init(id: UUID, date: Date, payload: Data) { self.id = id; self.date = date; self.payload = payload }
    }
    @Model final class RecipeRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class SavedMealRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class TargetRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class NutritionSettingsRecord {
        @Attribute(.unique) var key: String
        var payload: Data
        init(payload: Data) { key = "nutrition"; self.payload = payload }
    }
}
